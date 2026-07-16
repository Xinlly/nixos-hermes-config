# modules/feishu-card.nix — Hermes 飞书流式卡片侧车，Nix 声明式部署
#
# 架构:
#   Hermes Gateway (patched) → POST /events → Feishu Card Sidecar (127.0.0.1:8765)
#     → Feishu Open API → 飞书客户端卡片
#
# 三个组件:
#   ① feishuCardPackage — hermes-feishu-streaming-card Python 包
#   ② patchedGateway — AST 注入飞书卡片 hook 的 gateway/run.py
#   ③ sidecar systemd — 独立 HTTP 服务处理卡片渲染
{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.services.hermesFeishuCard;

  # ① Python 包: hermes-feishu-streaming-card v3.6.2
  feishuCardPackage = pkgs.python312Packages.buildPythonPackage {
    pname = "hermes-feishu-streaming-card";
    version = "3.6.2";
    format = "pyproject";
    src = inputs.hermes-feishu-card;
    nativeBuildInputs = [ pkgs.python312Packages.setuptools ];
    propagatedBuildInputs = with pkgs.python312Packages; [ aiohttp pyyaml ];
    doCheck = false;
    pythonImportsCheck = [ "hermes_feishu_card" ];
  };

  # ② 打补丁的 gateway/run.py — AST 注入 Feishu 卡片 hook
  # 照搬 nixos-hermes 的 opusCtypesShim 模式: 构建时生成，PYTHONPATH 注入
  #
  # 合并 feishu-card 及所有 Python 依赖到单个环境路径
  feishuCardEnv = pkgs.python312.withPackages (ps: [
    feishuCardPackage
    ps.aiohttp
    ps.pyyaml
  ]);

  patchedGateway = pkgs.runCommand "hermes-feishu-card-gateway" {
    nativeBuildInputs = [ pkgs.python312Packages.python feishuCardPackage ];
  } ''
    mkdir -p $out/gateway
    python3 <<PYEOF
    from hermes_feishu_card.install.patcher import apply_patch

    src_path = "${inputs.hermes-agent}/gateway/run.py"
    with open(src_path, encoding="utf-8") as f:
        original = f.read()

    patched = apply_patch(original, strategy="gateway_run_013_plus")

    with open("$out/gateway/run.py", "w", encoding="utf-8") as f:
        f.write(patched)
    with open("$out/gateway/__init__.py", "w", encoding="utf-8") as f:
        f.write("")
    print(f"[feishu-card] patched gateway/run.py ({len(patched)} bytes)")
    PYEOF
  '';

  # ②b 打补丁的 cron/scheduler.py — AST 注入 cron delivery hook
  # _deliver_result 函数在 cron/scheduler.py 中，不在 gateway/run.py 中
  patchedCron = pkgs.runCommand "hermes-feishu-card-cron" {
    nativeBuildInputs = [ pkgs.python312Packages.python feishuCardPackage ];
  } ''
    mkdir -p $out/cron
    python3 <<PYEOF
    from hermes_feishu_card.install.patcher import apply_cron_patch

    src_path = "${inputs.hermes-agent}/cron/scheduler.py"
    with open(src_path, encoding="utf-8") as f:
        original = f.read()

    patched = apply_cron_patch(original)

    with open("$out/cron/scheduler.py", "w", encoding="utf-8") as f:
        f.write(patched)
    with open("$out/cron/__init__.py", "w", encoding="utf-8") as f:
        f.write("")
    print(f"[feishu-card] patched cron/scheduler.py ({len(patched)} bytes)")
    PYEOF
  '';
in
{
  options.services.hermesFeishuCard = {
    enable = lib.mkEnableOption "Hermes Feishu streaming card sidecar";
    patchedGateway = lib.mkOption {
      type = lib.types.package;
      internal = true;
      description = "Patched gateway/run.py derivation (set automatically)";
    };
    patchedCron = lib.mkOption {
      type = lib.types.package;
      internal = true;
      description = "Patched cron/scheduler.py derivation (set automatically)";
    };
    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      description = "hermes-feishu-streaming-card Python package";
    };
  };

  config = lib.mkIf cfg.enable {
    services.hermesFeishuCard.package = lib.mkDefault feishuCardPackage;
    services.hermesFeishuCard.patchedGateway = lib.mkDefault patchedGateway;
    services.hermesFeishuCard.patchedCron = lib.mkDefault patchedCron;

    # ③ 侧车 systemd 服务 — 独立 HTTP 服务
    # 直跑 runner 模块（Type=simple），不再走 cli start 的 fork/exit 模式
    systemd.services.hermes-feishu-sidecar = {
      description = "Hermes Feishu Streaming Card Sidecar";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      requires = [ "hermes-agent.service" ];

      serviceConfig = {
        User = config.services.hermes-agent.user;
        Group = config.services.hermes-agent.group;
        # FEISHU_APP_ID / FEISHU_APP_SECRET 等密钥从 .env.secrets 注入
        EnvironmentFile = "/var/lib/hermes/.hermes/.env.secrets";
        # 用 withPackages 环境的 Python 直接运行 runner（含所有依赖）
        ExecStart = "${feishuCardEnv}/bin/python -m hermes_feishu_card.runner --config /var/lib/hermes/.hermes_feishu_card/config.yaml";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/hermes/.hermes_feishu_card";
        Restart = "always";
        RestartSec = "5s";
        WorkingDirectory = config.services.hermes-agent.workingDirectory;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [ config.services.hermes-agent.stateDir ];
        UMask = "0007";
      };
    };
  };
}
