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
        listen = "127.0.0.1:6767";
        cors.allowedOrigins = [ "https://app.paseo.sh" ];
        relay.enabled = true;
      };
      app.baseUrl = "https://app.paseo.sh";

      agents.providers.hermes = {
        extends = "acp";
        label = "Hermes";
        description = "Nous Research self-improving AI agent";
        # 用系统 PATH 中带 shim 的 hermes wrapper（注入 PYTHONPATH）
        command = [ "/run/current-system/sw/bin/hermes" "acp" ];
        # 显式钉死真实 HOME；overlay 合并到完整环境，PATH 等照常继承
        env.HOME = "/var/lib/hermes";
      };
    };
  };
}
