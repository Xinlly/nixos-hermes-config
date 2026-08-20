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
        cron_mode = "smart";  # cron 任务审批模式（v0.19+）：smart | manual | deny | off
      };
      security = { redact_secrets = true; };
      privacy = { redact_pii = false; };

      # 模型 — 火山引擎 Ark Code
      model = {
        default = "ark-code-latest";
        provider = "ark";
      };

      # TTS — 自定义 MiMo 提供商（xiaomiTTS2OpenAITTSAPI 代理）
      tts = {
        provider = "mimo";
        providers = {
          mimo = {
            type = "command";
            command = "${pkgs.python3}/bin/python3 /var/lib/hermes/workspace/projects/our/xiaomiTTS2OpenAITTSAPI/hermes_mimo_tts_wrapper.py {input_path} {output_path}";
            output_format = "opus";   # opus → 飞书原生语音消息（audio 类型）
            voice_compatible = true;  # 告诉 Hermes 此 provider 支持语音气泡投递，自动做 container 修复/转码兜底
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

      # 上下文压缩
      compression = {
        enabled = true;
        threshold = 0.50;        # 上下文 50% 触发
        target_ratio = 0.20;
        protect_last_n = 35;     # 保护最近 35 条消息
        protect_first_n = 3;
        tail_mode = "lean";      # v0.20 精简尾部模式
        min_tail_user_messages = 5;
        proactive_prune_tokens = 8000; # 主动裁剪 8k tokens 以上大工具输出
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
        ark = {
          base_url = "https://ark.cn-beijing.volces.com/api/coding";
          key_env = "ARK_API_KEY";
          name = "火山引擎 Ark";
          transport = "anthropic_messages";
        };
      };

      # 主模型备援 — 主模型失败时自动切换
      fallback_model = {
        provider = "minimax-cn";
        model = "MiniMax-M3";
      };

      # 辅助任务模型配置
      auxiliary = {
        vision = {
          provider = "minimax-cn";
          model = "MiniMax-M3";
        };
        compression = {
          provider = "deepseek";
          model = "deepseek-v4-flash";
        };
        # 轻量任务
        title_generation = { provider = "deepseek"; model = "deepseek-v4-flash"; };
        skills_hub        = { provider = "deepseek"; model = "deepseek-v4-flash"; };
        approval          = { provider = "deepseek"; model = "deepseek-v4-flash"; };
        mcp               = { provider = "deepseek"; model = "deepseek-v4-flash"; };
        tts_audio_tags    = { provider = "deepseek"; model = "deepseek-v4-flash"; };
        profile_describer = { provider = "deepseek"; model = "deepseek-v4-flash"; };
        monitor           = { provider = "deepseek"; model = "deepseek-v4-flash"; };
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
              oc_c5d502d7f1333cabc66ec4d5038ecbb1 = {
                policy = "open";
                require_mention = false;
              };
              oc_0b9b107979ff669cca767c6a796e5599 = {
                policy = "open";
                require_mention = false;
              };
              oc_d549896310272064b5c2eba1d97bca0c = {
                policy = "open";
                require_mention = false;
              };
            };
          };
        };
      };

      # Agent 行为
      agent = { max_turns = 500; };
      # 白名单工具组 — PoloAPI 限 128 tools，all=144，裁剪不必要组
      toolsets = [ "web" "terminal" "file" "skills" "vision" "tts" "todo" "memory" "session_search" "cronjob" "computer_use" "clarify" "execute_code" "delegate_task" "image_generate" "close_terminal" "read_terminal" "feishu_doc_read" "feishu_drive_add_comment" "feishu_drive_list_comments" "feishu_drive_list_comment_replies" "feishu_drive_reply_comment" "project_create" "project_list" "project_switch" ];

      # Superpowers workflow 暂停：保留文件备份，停止自动加载；改用 Matt Pocock skills 试运行。
      # 仅暴露 hermes/skills 适配层，不直接加载上游完整 skills/ 树。
      skills = {
        external_dirs = [ "/var/lib/hermes/workspace/projects/our/skills/hermes/skills" ];
        disabled = [
          "task-complexity-assessment"
          "brainstorming"
          "writing-plans"
          "subagent-driven-development"
          "test-driven-development"
          "systematic-debugging"
          "verification-before-completion"
          "requesting-code-review"
          "simplify-code"
          "research-first-workflow"
          "spike"
          "skill-evaluation"
          "plan"
        ];
      };

      # MCP 工具服务器
      mcp_servers = {
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
        siyuan_sisyphus = {
          command = "${pkgs.nodejs_22}/bin/node";
          args = [ "/mnt/d/Users/Admin0/SiYuan/data/plugins/siyuan-plugins-mcp-sisyphus/mcp-server.cjs" ];
          env = {
            SIYUAN_API_URL = "http://127.0.0.1:6806";
            SIYUAN_TOKEN = "\${SIYUAN_TOKEN}";
          };
        };
        cua-driver = {
          command = "/mnt/c/Users/Admin0/AppData/Local/Programs/Cua/cua-driver/bin/cua-driver.exe";
          args = [ "mcp" ];
        };
      };
    };

    # ── Python 依赖组 ──
    extraDependencyGroups = [ "feishu" "hindsight" "voice" "messaging" "anthropic" ];

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
      MINIMAX_CN_BASE_URL = "https://api.minimaxi.com/anthropic";
      HTTP_PROXY = "http://127.0.0.1:35353";
      HTTPS_PROXY = "http://127.0.0.1:35353";
      HERMES_SEARCH_PROXY = "http://127.0.0.1:35353";
      AGENT_BROWSER_PROXY = "http://127.0.0.1:35353";
      AGENT_BROWSER_PROXY_BYPASS = "localhost,127.0.0.1";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/tmp/dbus-session";  # soffice headless 绕过 /run/user/UID 权限
      AGENT_BROWSER_AUTO_CONNECT = "true";
      # CUA driver — computer_use 工具调用宿主机 Windows 上的 cua-driver.exe
      HERMES_CUA_DRIVER_CMD = "/mnt/c/Users/Admin0/AppData/Local/Programs/Cua/cua-driver/bin/cua-driver.exe";
    };
    # ── 机密环境变量（追加入 .env 第二部分）──
    environmentFiles = [ "/var/lib/hermes/.hermes/.env.secrets" ];
  };
}
