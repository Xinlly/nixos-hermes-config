# modules/hermes/runtime.nix — Hermes 运行时推导（portaudio, shim, wrapper, pythonPath）
#
# 这些是各子模块依赖的通用构建产物，改频极低。
# 通过 config.services.hermesRuntime.* 导出供 agent.nix / services.nix 引用。
{ config, pkgs, lib, ... }:
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
  # ACP backport 已由上游接替，保留补丁以便回查：
  # patches/hermes-agent/0001-acp-fix-none-final-response.patch
  # 新版的 wheel 已打包顶层模块，因此停用旧的 sys.path 源码覆盖。
  # 旧 httpx 全局代理补丁也停用，改由 HTTP_PROXY / NO_PROXY 控制请求。

  # NixOS 的 ctypes.find_library 找不到 store 内的 PortAudio / PulseAudio。
  shim = pkgs.writeTextDir "sitecustomize.py" ''
    import ctypes.util as _cu

    _orig_find_library = _cu.find_library

    def _patched_find_library(name, *args, **kwargs):
        if name == "portaudio":
            return "${portaudio}/lib/libportaudio.so"
        if name == "pulse":
            return "${pkgs.libpulseaudio}/lib/libpulse.so"
        return _orig_find_library(name, *args, **kwargs)

    _cu.find_library = _patched_find_library
  '';

  # ═══════════════════════════════════════════════
  # CLI wrapper — hermes-u 命令
  # ═══════════════════════════════════════════════
  # 自动: cd workspace → sudo -u hermes → 注入 PYTHONPATH → 运行 hermes
  hermesUWrapper = pkgs.writeShellScriptBin "hermes-u" ''
    set -e
    export PYTHONPATH="${pythonPath}"
    cd /var/lib/hermes/workspace || true
    if [ "$(whoami)" != "hermes" ]; then
      export PATH="/etc/profiles/per-user/hermes/bin:$PATH"
      exec sudo -u hermes env PYTHONPATH="$PYTHONPATH" PATH="$PATH" "$0" "$@"
    fi
    exec hermes "$@"
  '';

  # ═══════════════════════════════════════════════
  # hermes 命令包装 — sitecustomize 内置到裸 hermes
  # ═══════════════════════════════════════════════
  hermesAgentPkg = config.services.hermes-agent.package;
  python = hermesAgentPkg.python;
  hermesWithShim = pkgs.runCommand "hermes-agent-with-shim" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p $out/bin
    for bin in hermes hermes-acp hermes-agent; do
      makeWrapper ${hermesAgentPkg}/bin/$bin $out/bin/$bin \
        --prefix PYTHONPATH : "${pythonPath}"
    done
  '';

  # 原生扩展必须与上游 Hermes 自带解释器使用同一 Python ABI。
  documentDeps = python.pkgs.requiredPythonModules (with python.pkgs; [
    pymupdf
    pymupdf4llm
    openpyxl
    pandas
    markitdown
    xlsxwriter
  ]);
  documentPath = lib.makeSearchPath python.sitePackages documentDeps;
  pythonPath = "${shim}:${config.services.hermesRuntime.hindsightClient}/${python.sitePackages}:${documentPath}";
in
{
  options.services.hermesRuntime = {
    portaudio = lib.mkOption { type = lib.types.package; internal = true; };
    shim = lib.mkOption { type = lib.types.package; internal = true; };
    hindsightClient = lib.mkOption { type = lib.types.package; internal = true; };
    hermesUWrapper = lib.mkOption { type = lib.types.package; internal = true; };
    hermesWithShim = lib.mkOption { type = lib.types.package; internal = true; };
    pythonPath = lib.mkOption { type = lib.types.str; internal = true; };
  };

  config = {
    services.hermesRuntime = {
      inherit portaudio shim hermesUWrapper hermesWithShim pythonPath;
    };

    # hermes-u 加入系统 PATH
    # hermesWithShim 用 mkBefore 排在 systemPackages 前面，
    # 确保裸 hermes 命令走 wrapper（自动注入 sitecustomize）
    environment.systemPackages = lib.mkBefore [ hermesUWrapper hermesWithShim ];

    # sudoers: xavier 免密以 hermes 身份执行 hermes-u
    security.sudo.extraRules = [{
      users = [ "xavier" ];
      commands = [{
        command = "${hermesUWrapper}/bin/hermes-u";
        options = [ "NOPASSWD" ];
      }];
      runAs = "hermes";
    }];
  };
}
