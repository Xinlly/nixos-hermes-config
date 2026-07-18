# modules/hermes/runtime.nix — Hermes 运行时推导（portaudio, shim, wrapper, pythonPath）
#
# 这些是各子模块依赖的通用构建产物，改频极低。
# 通过 config.services.hermesRuntime.* 导出供 agent.nix / services.nix 引用。
{ config, pkgs, lib, inputs, ... }:
let
  # ═══════════════════════════════════════════════
  # portaudio — 编译 PulseAudio 后端（替代 nixpkgs 默认 ALSA 版本）
  # 默认 nixpkgs portaudio: buildInputs=[alsa, jack], 无 PulseAudio
  # WSL2 无 ALSA 硬件 → 只能通过 PulseAudio 接入音频设备
  # 此 derivation 从 portaudio 源码编译，链接 libpulse-simple
  # ═══════════════════════════════════════════════
  portaudio = pkgs.stdenv.mkDerivation {
    pname = "portaudio";
    version = "git-2024";
    # pa_stable tarball 不含 PulseAudio 后端源码，用 GitHub master
    src = pkgs.fetchFromGitHub {
      owner = "PortAudio";
      repo = "portaudio";
      rev = "master";
      sha256 = "sha256-xK6FxsbjTpPQ5YISDOlXL6O6D9W3q7hD/gRsmD/ndPA=";
    };
    nativeBuildInputs = with pkgs; [ cmake pkg-config ];
    buildInputs = [ pkgs.libpulseaudio.dev ];
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DPA_BUILD_SHARED_LIBS=ON"
      "-DCMAKE_INSTALL_LIBDIR=lib"
      "-DCMAKE_INSTALL_INCLUDEDIR=include"
    ];
  };

  # ═══════════════════════════════════════════════
  # sitecustomize.py — 七合一 Python 启动 shim
  # ═══════════════════════════════════════════════
  # ① PortAudio ctypes 劫持: NixOS CPython no-ldconfig 补丁导致
  #    ctypes.util.find_library("portaudio") 始终返回 None。
  #    直接返回 Nix store 中 libportaudio.so 路径。
  # ② libpulse 劫持: 同①，PortAudio PulseAudio 后端需要 libpulse.so。
  #    LD_LIBRARY_PATH 已在 serviceConfig 设好，此处再做 ctypes 兜底。
  # ③ hermes_cli 源码扩展: v0.17.0 密封 venv 仅含 hermes_cli 顶层，
  #    遗漏 proxy 等子模块。注入源码路径供 gateway 导入。
  # ④ cron 源码扩展: gateway/run.py 导入 cron.scheduler，但 cron 未打包进密封 venv。
  #    注入源码路径（与 ③ 同源的 hermes-agent flake input）。
  # ⑤ 飞书卡片 gateway 覆盖: sealed venv site-packages 在 sys.path[1]，
  #    PYTHONPATH 排在其后。从环境变量 HERMES_PATCHED_GATEWAY 读取路径，
  #    注入 gateway.__path__[0]，确保补丁版 gateway/run.py 优先加载。
  # ⑦ web_search 代理注入 — 劫持 httpx，从 HERMES_SEARCH_PROXY 环境变量读取代理
  shim = pkgs.writeTextDir "sitecustomize.py" ''
    import ctypes.util as _cu
    import os as _os
    import sys as _sys
    from pathlib import Path as _Path

    _PORTAUDIO_PATH = "${portaudio}/lib/libportaudio.so"
    _PULSE_PATH = "${pkgs.libpulseaudio}/lib/libpulse.so"
    _HERMES_CLI_SOURCE = "${inputs.hermes-agent}/hermes_cli"
    _HERMES_CRON_SOURCE = "${inputs.hermes-agent}/cron"
    _orig_find_library = _cu.find_library

    def _patched_find_library(name, *args, **kwargs):
        if name == "portaudio":
            return _PORTAUDIO_PATH
        if name == "pulse":
            return _PULSE_PATH
        return _orig_find_library(name, *args, **kwargs)

    _cu.find_library = _patched_find_library

    try:
        import hermes_cli as _hermes_cli
        if hasattr(_hermes_cli, "__path__") and _HERMES_CLI_SOURCE not in _hermes_cli.__path__:
            _hermes_cli.__path__.append(_HERMES_CLI_SOURCE)
    except ImportError:
        pass

    try:
        import cron as _hermes_cron
        if hasattr(_hermes_cron, "__path__") and _HERMES_CRON_SOURCE not in _hermes_cron.__path__:
            _hermes_cron.__path__.append(_HERMES_CRON_SOURCE)
    except ImportError:
        pass

    # ⑤ 飞书卡片 gateway 覆盖
    _pg = _os.environ.get("HERMES_PATCHED_GATEWAY", "")
    if _pg:
        try:
            import gateway as _gw
            _patched = _pg + "/gateway"
            if _patched not in _gw.__path__:
                _gw.__path__.insert(0, _patched)
        except Exception:
            pass

    # ⑦ web_search 代理注入 — 劫持 httpx，从 HERMES_SEARCH_PROXY 环境变量读取代理
    _search_proxy = _os.environ.get("HERMES_SEARCH_PROXY", "")
    if _search_proxy:
        try:
            import httpx as _httpx
            _orig_async_init = _httpx.AsyncClient.__init__
            _orig_client_init = _httpx.Client.__init__

            def _patched_async_init(self, *args, **kwargs):
                kwargs.setdefault("proxy", _search_proxy)
                _orig_async_init(self, *args, **kwargs)

            def _patched_client_init(self, *args, **kwargs):
                kwargs.setdefault("proxy", _search_proxy)
                _orig_client_init(self, *args, **kwargs)

            _httpx.AsyncClient.__init__ = _patched_async_init
            _httpx.Client.__init__ = _patched_client_init
        except Exception:
            pass
  '';

  # ═══════════════════════════════════════════════
  # CLI wrapper — hermes-w 命令
  # ═══════════════════════════════════════════════
  # 自动: cd workspace → sudo -u hermes → 注入 PYTHONPATH → 运行 hermes
  hermesWrapper = pkgs.writeShellScriptBin "hermes-w" ''
    set -e
    export PYTHONPATH="${shim}"
    cd /var/lib/hermes/workspace || true
    if [ "$(whoami)" != "hermes" ]; then
      export PATH="/etc/profiles/per-user/hermes/bin:$PATH"
      exec sudo -u hermes env PYTHONPATH="$PYTHONPATH" PATH="$PATH" "$0" "$@"
    fi
    exec hermes "$@"
  '';

  # pymupdf + 其传递依赖（含 mupdf Python 绑定和原生 .so）
  # requiredPythonModules 展开传递依赖，makeSearchPath 构建完整 PYTHONPATH
  pymupdfDeps = pkgs.python312.pkgs.requiredPythonModules [ pkgs.python312Packages.pymupdf pkgs.python312Packages.pymupdf4llm ];
  pymupdfPath = lib.makeSearchPath "lib/python3.12/site-packages" pymupdfDeps;

  # openpyxl + pandas（Excel 编辑能力，pandas 含 numpy 等 C 扩展）
  officeDeps = pkgs.python312.pkgs.requiredPythonModules [ pkgs.python312Packages.openpyxl pkgs.python312Packages.pandas ];
  officePath = lib.makeSearchPath "lib/python3.12/site-packages" officeDeps;

  # ═══════════════════════════════════════════════
  # PYTHONPATH — 唯一定义点
  # ═══════════════════════════════════════════════
  # Gateway systemd 单元、.env 文件、CLI wrapper 三处共用同一值。
  # 包含: feishu-card 包 + 补丁版 gateway + sitecustomize.py shim + pymupdf + office(含传递依赖)
  pythonPath = "${config.services.hermesFeishuCard.package}/lib/python3.12/site-packages:${config.services.hermesFeishuCard.patchedGateway}:${shim}:${pymupdfPath}:${officePath}";
in
{
  options.services.hermesRuntime = {
    portaudio = lib.mkOption { type = lib.types.package; internal = true; };
    shim = lib.mkOption { type = lib.types.package; internal = true; };
    hermesWrapper = lib.mkOption { type = lib.types.package; internal = true; };
    pythonPath = lib.mkOption { type = lib.types.str; internal = true; };
  };

  config = {
    services.hermesRuntime = {
      inherit portaudio shim hermesWrapper pythonPath;
    };

    # hermes-w 加入系统 PATH
    environment.systemPackages = [ hermesWrapper ];

    # sudoers: xavier 免密以 hermes 身份执行 hermes-w
    security.sudo.extraRules = [{
      users = [ "xavier" ];
      commands = [{
        command = "${hermesWrapper}/bin/hermes-w";
        options = [ "NOPASSWD" ];
      }];
      runAs = "hermes";
    }];
  };
}
