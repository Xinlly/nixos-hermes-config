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
  # sitecustomize.py — 四合一 Python 启动 shim
  # ═══════════════════════════════════════════════
  # ① PortAudio ctypes 劫持: NixOS CPython no-ldconfig 补丁导致
  #    ctypes.util.find_library("portaudio") 始终返回 None。
  #    直接返回 Nix store 中 libportaudio.so 路径。
  # ② libpulse 劫持: 同①，PortAudio PulseAudio 后端需要 libpulse.so。
  #    LD_LIBRARY_PATH 已在 serviceConfig 设好，此处再做 ctypes 兜底。
  # ③ 源码扩展: v0.20 密封 venv 仅含 site-packages 中的 hermes_cli 等子模块，
  #    遗漏 registration_lifecycle / run_agent / cli / toolsets 等顶层模块。
  #    注入整个源码根目录，确保 hermes_cli.plugins 等 import 能找到顶层模块。
  # ⑦ web_search 代理注入 — 劫持 httpx，从 HERMES_SEARCH_PROXY 环境变量读取代理
  #
  # 已删除的历史 patch:
  #   ⑤ 飞书卡片 gateway 覆盖 — 插件自己做 runtime monkey patching
  #   ⑧ CUA WSL manifest 路径 — v0.20 上游原生支持 HERMES_CUA_DRIVER_CMD + WSL 路径转换
  shim = pkgs.writeTextDir "sitecustomize.py" ''
    import ctypes.util as _cu
    import os as _os
    import sys as _sys
    from pathlib import Path as _Path

    _PORTAUDIO_PATH = "${portaudio}/lib/libportaudio.so"
    _PULSE_PATH = "${pkgs.libpulseaudio}/lib/libpulse.so"
    _HERMES_SOURCE_ROOT = "${inputs.hermes-agent}"
    _orig_find_library = _cu.find_library

    def _patched_find_library(name, *args, **kwargs):
        if name == "portaudio":
            return _PORTAUDIO_PATH
        if name == "pulse":
            return _PULSE_PATH
        return _orig_find_library(name, *args, **kwargs)

    _cu.find_library = _patched_find_library

    # ③ 源码扩展 — 把 hermes-agent 源码根目录插入 sys.path 最前面，
    #    让密封 venv 找不到的顶层模块（registration_lifecycle / run_agent /
    #    cli / toolsets / model_tools 等）能从源码直接导入。
    if _HERMES_SOURCE_ROOT not in _sys.path:
        _sys.path.insert(0, _HERMES_SOURCE_ROOT)

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

  # openpyxl + pandas + markitdown + xlsxwriter（Excel编辑 + Office文档→Markdown + 图表嵌入，pandas/markitdown 含 numpy 等 C 扩展）
  officeDeps = pkgs.python312.pkgs.requiredPythonModules [ pkgs.python312Packages.openpyxl pkgs.python312Packages.pandas pkgs.python312Packages.markitdown pkgs.python312Packages.xlsxwriter ];
  officePath = lib.makeSearchPath "lib/python3.12/site-packages" officeDeps;

  # ═══════════════════════════════════════════════
  # PYTHONPATH — 唯一定义点
  # ═══════════════════════════════════════════════
  # Gateway systemd 单元、.env 文件、CLI wrapper 三处共用同一值。
  # 包含: sitecustomize.py shim + pymupdf + office(含传递依赖)
  # 注: 飞书卡片插件通过 hermes-plugins.nix 的 extraPlugins 加载，不在此处
  pythonPath = "${shim}:${pymupdfPath}:${officePath}";
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
