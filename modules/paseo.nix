# modules/paseo.nix — Paseo 多 coding agent 编排 daemon
#
# 官方 flake：github:getpaseo/paseo（flake.nix 已声明 input 并挂 nixosModule，
# 包由该 module 以 mkDefault 指向 flake 自带包，无需在此指定 package）。
#
# 以 hermes 用户运行：spawn 的 `hermes acp` 子进程复用 hermes 用户的
# /var/lib/hermes/.hermes 配置与凭证。注意 hermes 用户真实 HOME 是
# /var/lib/hermes（/home/hermes 不存在），故 dataDir 显式指定，
# 且给 hermes provider 显式注入 HOME，避免 /home/hermes 假设。
{ config, lib, pkgs, ... }:
{
  services.paseo = {
    enable = true;

    # 复用现有 hermes 系统账户（module 仅在 user=="paseo" 时才自建用户/组，
    # 故 group 也要显式给 hermes）
    user = "hermes";
    group = "hermes";
    dataDir = "/var/lib/hermes/.paseo";

    # 监听地址：module 用它生成 PASEO_LISTEN 环境变量，优先级高于 settings 里的
    # daemon.listen。要对所有网卡开放必须改这里，仅改 settings 不生效。
    listenAddress = "0.0.0.0";

    # 让 daemon spawn 的 agent 能找到用户 profile / 系统 PATH 中的 git、ssh、hermes
    inheritUserEnvironment = true;

    # relay：保持官方默认（hosted，外联 app.paseo.sh 做 E2EE 远程接入）
    relay = {
      enable = true;
      mode = "hosted";
    };

    # 声明式 config.json（每次服务启动由 Nix 渲染覆盖，勿用 CLI 手改）
    settings = {
      version = 1;
      daemon = {
        # listen 由顶层 listenAddress 经 PASEO_LISTEN 环境变量控制，此处不写
        cors.allowedOrigins = [ "https://app.paseo.sh" ];
        relay.enabled = true;

        # Inject the Paseo MCP server into spawned agents (was lost on 09-26 re-render)
        mcp.injectIntoAgents = true;
        browserTools.enabled = true;

        # Universal red lines, auto-appended to every agent's system prompt.
        # This is the ONLY reliable auto-injection channel (skills need skill_view).
        # Re-authored 2026-09-26 after the original literal was wiped (same 3 rules).
        appendSystemPrompt = ''
          1. Identity anchor: your role and project are the Paseo registration labels (role / project) and your parent chain (label paseo.parent-agent-id), assigned at creation. Do not investigate or re-assign your own identity; no identity archaeology.
          2. Sole delegation channel: spawn sub-work only via Paseo create_agent (or the Paseo CLI). Never use Hermes delegate_task inside a Paseo project.
          3. Stay in role: orchestrators/planners dispatch and coordinate; never personally perform product work (no product code edits, no builds beyond the orchestrator Gate).
        '';
      };
      app.baseUrl = "https://app.paseo.sh";

      agents = {
        skills.selection.mode = "all";

        providers.hermes = {
          extends = "acp";
          label = "哆啦";
          description = "哆啦是一个多功能的 AI 助手，能够处理各种任务和请求。";
          # 用系统 PATH 中带 shim 的 hermes wrapper（注入 PYTHONPATH）
          command = [ "/run/current-system/sw/bin/hermes" "acp" ];
          # 显式钉死真实 HOME；overlay 合并到完整环境，PATH 等照常继承
          env.HOME = "/var/lib/hermes";
        };

        # 管理者专用并列 provider：同一 hermes wrapper，但经 --profile manager
        # 使用独立 manager profile（modules/hermes/manager-profile.nix）。
        # 该 profile 的 config 已禁用 hermes-lark-streaming（飞书流式卡片不加载）。
        providers."hermes-manager" = {
          extends = "acp";
          label = "哆啦（管理者）";
          description = "管理者专用 Hermes（独立 manager profile）；该 profile 已禁用 hermes-lark-streaming，不加载飞书流式卡片插件。";
          command = [
            "/run/current-system/sw/bin/hermes"
            "--profile"
            "manager"
            "acp"
          ];
          # 与 hermes provider 一致：显式钉死真实 HOME，其余环境照常继承
          env.HOME = "/var/lib/hermes";
        };
      };
    };

    # 云端 STT（SiliconFlow，OpenAI 兼容）非敏感配置
    environment = {
      OPENAI_STT_BASE_URL = "https://api.siliconflow.cn/v1";
      STT_MODEL = "FunAudioLLM/SenseVoiceSmall";
      PASEO_DICTATION_STT_PROVIDER = "openai";
      PASEO_VOICE_STT_PROVIDER = "openai";
      PASEO_DICTATION_LANGUAGE = "zh";
      PASEO_VOICE_LANGUAGE = "zh";
    };
  };

  # 密钥仅引用路径；文件由人工创建，不进 nix/store/git
  systemd.services.paseo.serviceConfig.EnvironmentFile =
    [ "/var/lib/hermes/.paseo/secret.env" ];
}
