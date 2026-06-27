# hermes.nix — Hermes Agent 核心配置
#
# 涵盖: sitecustomize.py shim、PYTHONPATH 统一、CLI wrapper、
#       飞书卡片 hook 注入、VBAN 音频接收、服务选项声明
{ config, pkgs, inputs, ... }:
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
  # ③ hermes_cli 源码扩展: v0.17.0 密封 venv 仅含 hermes_cli 顶层，
  #    遗漏 proxy 等子模块。注入源码路径供 gateway 导入。
  # ④ cron 源码扩展: gateway/run.py 导入 cron.scheduler，但 cron 未打包进密封 venv。
  #    注入源码路径（与 ③ 同源的 hermes-agent flake input）。
  # ⑤ 飞书卡片 gateway 覆盖: sealed venv site-packages 在 sys.path[1]，
  #    PYTHONPATH 排在其后。从环境变量 HERMES_PATCHED_GATEWAY 读取路径，
  #    注入 gateway.__path__[0]，确保补丁版 gateway/run.py 优先加载。
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

  # sudoers: xavier 免密以 hermes 身份执行 hermes-w
  sudoHermesW = {
    users = [ "xavier" ];
    commands = [{
      command = "${hermesWrapper}/bin/hermes-w";
      options = [ "NOPASSWD" ];
    }];
    runAs = "hermes";
  };
in let
  # ═══════════════════════════════════════════════
  # PYTHONPATH — 唯一定义点
  # ═══════════════════════════════════════════════
  # Gateway systemd 单元、.env 文件、CLI wrapper 三处共用同一值。
  # 包含: feishu-card 包 + 补丁版 gateway + sitecustomize.py shim
  pythonPath = "${config.services.hermesFeishuCard.package}/lib/python3.12/site-packages:${config.services.hermesFeishuCard.patchedGateway}:${shim}";
in {
  # llm-agents.nix overlay — 提供 agent-browser、claude-code 等 AI 编码工具
  nixpkgs.overlays = [ inputs.llm-agents.overlays.default ];

  # 全局软件包
  environment.systemPackages = with pkgs; [ nodejs_22 gh ] ++ [ hermesWrapper ];

  # 插件开关
  services.hermesFeishuCard.enable = true;  # 飞书流式卡片
  services.vbanReceiver.enable = true;      # VBAN 音频接收器

  # sudo 规则
  security.sudo.extraRules = [ sudoHermesW ];

  # ═══════════════════════════════════════════════
  # Hermes Agent 服务
  # ═══════════════════════════════════════════════
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    stateDir = "/var/lib/hermes";
    workingDirectory = "/var/lib/hermes/workspace";

    # ── settings ──
    settings = {
      # 安全
      approvals = { mode = "manual"; };
      security = { redact_secrets = true; };
      privacy = { redact_pii = false; };

      # 模型 — DeepSeek V4 Pro
      model = {
        default = "deepseek-v4-pro";
        provider = "deepseek";
      };

      # TTS — Edge 中文语音（小晓）
      tts = {
        provider = "edge";
        edge = {
          voice = "zh-CN-XiaoxiaoNeural";
          speed = 1.2;
        };
      };

      # STT — 本地 faster-whisper (small 模型)
      stt = {
        enabled = true;
        provider = "local";
        local = { model = "small"; };
      };

      # 显示 — 中文、隐藏推理过程和费用
      display = {
        language = "zh";
        show_reasoning = false;
        show_cost = false;
      };

      # 流式输出
      streaming = { enabled = true; };

      # 终端 — 本地后端，cwd 与 workingDirectory 统一
      terminal = {
        backend = "local";
        timeout = 180;
        cwd = config.services.hermes-agent.workingDirectory;
      };

      # 记忆 — Hindsight 引擎
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
        memory_char_limit = 4000;
        user_char_limit = 1375;
        provider = "hindsight";
      };

      # 上下文压缩
      compression = {
        enabled = true;
        threshold = 0.50;
        target_ratio = 0.20;
      };

      # Agent 行为
      agent = { max_turns = 90; };
      toolsets = [ "all" ];

      # MCP 工具服务器 (npx)
      mcp_servers = {
        fetch = {
          command = "npx";
          args = [ "-y" "@modelcontextprotocol/server-fetch" ];
        };
        playwright = {
          command = "npx";
          args = [ "-y" "@playwright/mcp" ];
        };
        context7 = {
          command = "npx";
          args = [ "-y" "@upstash/context7-mcp" ];
        };
      };
    };

    # ── Python 依赖组 ──
    extraDependencyGroups = [ "feishu" "hindsight" "edge-tts" "voice" "messaging" ];

    # ── 额外系统包 ──
    extraPackages = [ portaudio pkgs.playwright-driver.browsers pkgs.llm-agents.agent-browser ];
    # portaudio 已由本地 derivation 编译 PulseAudio 后端
    # playwright-driver.browsers + agent-browser: 浏览器工具集

    # ── 非机密环境变量（写入 .env 第一部分）──
    environment = {
      PULSE_SERVER = "/mnt/wslg/PulseServer";   # WSLg 音频服务
      PYTHONPATH = pythonPath;                    # Python 模块搜索路径
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";  # 浏览器工具集
      AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.playwright-driver.browsers}/chromium-1223/chrome-linux64/chrome";
    };

    # ── 机密环境变量（追加入 .env 第二部分）──
    environmentFiles = [ "/var/lib/hermes/.hermes/.env.secrets" ];
  };

  # ═══════════════════════════════════════════════
  # systemd 环境变量 — Python 启动前必须就位
  # ═══════════════════════════════════════════════
  # Environment (systemd unit) 比 .env (shell source) 更早生效，
  # sitecustomize.py 在 Python 启动时就需要 PYTHONPATH。
  systemd.services.hermes-agent.serviceConfig.Environment = [
    "PYTHONPATH=${pythonPath}"
    "HERMES_PATCHED_GATEWAY=${config.services.hermesFeishuCard.patchedGateway}"
    "LD_LIBRARY_PATH=${pkgs.libpulseaudio}/lib"   # PortAudio dlopen libpulse 需要
    "no_proxy=localhost,127.0.0.1,::1"
  ];
}
