# hosts/wsl/hermes.nix — WSL2 变体：Hermes 全功能模块聚合
#
# 导入所有 Hermes 子模块。云服务器等不需要 Hermes 的变体跳过此文件即可。
{ ... }:
{
  imports = [
    ../../modules/hermes/runtime.nix
    ../../modules/hermes/agent.nix
    ../../modules/hermes/services.nix
    ../../modules/hermes/feishu-card.nix
    ../../modules/hermes/vban-receiver.nix
    ../../modules/hermes/hindsight.nix
  ];

  # 插件开关（仅此变体需要）
  services.hermesFeishuCard.enable = true;
  services.vbanReceiver.enable = true;
  services.vbanReceiver.port = 6980;
}
