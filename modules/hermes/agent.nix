# modules/hermes/agent.nix — Hermes Agent 服务配置（调频最高）
#
# 模型、TTS、STT、MCP、内存、压缩、工具集等高频调整项集中于此。
# 引用 config.services.hermesRuntime.* 获取 portaudio/pythonPath。
{ config, pkgs, lib, inputs, ... }:
let
  cfg = config.services.hermesRuntime;
in
{
  # llm-agents.nix overlay — 提供 agent-browser、claude-code 等 AI 编码工具
  nixpkgs.overlays = [ inputs.llm-agents.overlays.default ];

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    stateDir = "/var/lib/hermes";
    workingDirectory = "/var/lib/hermes/workspace";

    # ── settings ──
    settings = {
      # 安全
      approvals = { 
        mode = "smart";    # smart | manual | off — LLM 自动判断，不确定时弹确认
        timeout = 60;      # 等待用户响应的秒数
      };
      security = { redact_secrets = true; };
      privacy = { redact_pii = false; };

      # 模型 — Xiaomi MiMo
      model = {
        default = "mimo-v2.5";
        provider = "xiaomi";
      };

      # TTS — 自定义 MiMo 提供商（xiaomiTTS2OpenAITTSAPI 代理）
      tts = {
        provider = "mimo";
        providers = {
          mimo = {
            type = "command";
            command = "${pkgs.python3}/bin/python3 /var/lib/hermes/workspace/projects/our/xiaomiTTS2OpenAITTSAPI/hermes_mimo_tts_wrapper.py {input_path} {output_path}";
            output_format = "mp3";
          };
        };
      };

      # STT — 本地 faster-whisper (small 模型)
      stt = {
        enabled = true;
        provider = "local";
        local = { model = "small"; };
      };

      # 流式输出
      streaming = { enabled = true; };

      # Lark Streaming 卡片配置
      hermes_lark_streaming = {
        panel_expanded = false;
        streaming_panel_expanded = false;
        print_strategy = "delay";
        print_step = 4;
        flush_interval_ms = 200;
        card_ttl_sec = 600;
        max_tool_steps = 20;
        max_reasoning_rounds = 20;
        footer = {
          show_label = false;
          fields = [
            ["status" "elapsed" "model" "cost"]
            ["tokens" "context"]
          ];
        };
      };

      # 显示 — 中文、显示推理过程
      display = {
        language = "zh";
        show_reasoning = true;
        show_cost = false;
      };
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

      # 上下文压缩（何时触发）
      compression = {
        enabled = true;
        threshold = 0.50;
        target_ratio = 0.20;
      };

      # 自定义提供商
      providers = {
        xfyun = {
          base_url = "https://maas-coding-api.cn-huabei-1.xf-yun.com/v2";
          key_env = "XFYUN_API_KEY";
          name = "讯飞 Coding Plan";
        };
        poloapi = {
          base_url = "https://poloapi.top/v1";
          key_env = "POLOAPI_API_KEY";
          name = "PoloAPI";
        };
      };

      # 主模型备援 — 主模型失败时自动切换
      fallback_model = {
        provider = "deepseek";
        model = "deepseek-v4-pro";
      };

      # 辅助任务模型配置
      auxiliary = {
        vision = {
          provider = "xiaomi";
          model = "mimo-v2.5";
        };
        compression = {
          provider = "deepseek";
          model = "deepseek-v4-flash";
        };
        # 轻量任务 — 全部用讯飞 DeepSeek V3.2
        title_generation = { provider = "xfyun"; model = "xopdeepseekv32"; };
        skills_hub        = { provider = "xfyun"; model = "xopdeepseekv32"; };
        approval          = { provider = "xfyun"; model = "xopdeepseekv32"; };
        mcp               = { provider = "xfyun"; model = "xopdeepseekv32"; };
        tts_audio_tags    = { provider = "xfyun"; model = "xopglmv47flash"; };
        profile_describer = { provider = "xfyun"; model = "xopdeepseekv32"; };
        monitor           = { provider = "xfyun"; model = "xopdeepseekv32"; };
      };

      # 平台配置
      platforms = {
        telegram = {
          enable = false;
        };
        feishu = {
          extra = {
            group_rules = {
              oc_ddc26398eb2e74e92bfd1dd34d0e54e8 = {
                policy = "open";
                require_mention = true;
              };
              oc_6afdb726739fc42142e2533426bddeac = {
                policy = "open";
                require_mention = true;
              };
              oc_c788a9c6a78ae06ddccf014a468fb74d = {
                policy = "open";
                require_mention = true;
              };
            };
          };
        };
      };

      # Agent 行为
      agent = { max_turns = 90; };
      # 白名单工具组 — PoloAPI 限 128 tools，all=144，裁剪不必要组
      toolsets = [ "terminal" "file" "browser" "skills" "web" "vision" "tts" "todo" "memory" "session_search" "cronjob" "computer_use" "clarify" "execute_code" "delegate_task" "image_generate" "close_terminal" "read_terminal" "feishu_doc_read" "feishu_drive_add_comment" "feishu_drive_list_comments" "feishu_drive_list_comment_replies" "feishu_drive_reply_comment" "project_create" "project_list" "project_switch" ];

      # MCP 工具服务器
      mcp_servers = {
        fetch = {
          command = "npx";
          args = [ "-y" "@modelcontextprotocol/server-fetch" ];
        };
        playwright = {
          command = "npx";
          args = [ "-y" "@playwright/mcp" "--cdp-endpoint" "http://127.0.0.1:9223" ];
        };
        context7 = {
          command = "npx";
          args = [ "-y" "@upstash/context7-mcp" ];
        };
        electerm = {
          url = "http://127.0.0.1:30837/mcp";
        };
        # cua-driver disabled — PoloAPI 限 128 tools
        # cua-driver = {
        #   command = "/mnt/c/Users/Admin0/AppData/Local/Programs/Cua/cua-driver/bin/cua-driver.exe";
        #   args = [ "mcp" ];
        # };
      };
    };

    # ── Python 依赖组 ──
    extraDependencyGroups = [ "feishu" "hindsight" "voice" "messaging" ];

    # ── 额外系统包 ──
    extraPackages = [
      cfg.portaudio
      pkgs.playwright-driver.browsers
      pkgs.llm-agents.agent-browser
      pkgs.uv  # Python包管理器，参考 nixos-hermes 项目
    ];
    # portaudio 已由本地 derivation 编译 PulseAudio 后端
    # playwright-driver.browsers + agent-browser: 浏览器工具集
    # uv: 参考 nixos-hermes 项目，用于运行时安装 Python 包

    # ── 非机密环境变量（写入 .env 第一部分）──
    environment = {
      PULSE_SERVER = "/mnt/wslg/PulseServer";   # WSLg 音频服务
      PYTHONPATH = cfg.pythonPath;                # Python 模块搜索路径
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";  # 浏览器工具集
      AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.playwright-driver.browsers}/chromium-1223/chrome-linux64/chrome";
      # API Server — hermes-desktop / OpenAI 兼容前端接入端口
      API_SERVER_HOST = "127.0.0.1";
      API_SERVER_PORT = "8642";
      # 时区配置（北京时间）
      HERMES_TIMEZONE = "Asia/Shanghai";
    };
    # ── 机密环境变量（追加入 .env 第二部分）──
    environmentFiles = [ "/var/lib/hermes/.hermes/.env.secrets" ];
  };
}
