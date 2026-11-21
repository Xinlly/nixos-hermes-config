# hosts/wsl/hermes.nix — WSL2 变体：Hermes 全功能模块聚合
#
# 导入所有 Hermes 子模块。云服务器等不需要 Hermes 的变体跳过此文件即可。
{ config, lib, ... }:
let
  hermes = config.services.hermes-agent;
  hermesHome = "${hermes.stateDir}/.hermes";
in
{
  imports = [
    ../../modules/hermes/runtime.nix
    ../../modules/hermes/agent.nix
    ../../modules/hermes/services.nix
    ../../modules/hermes/hermes-plugins.nix
    ../../modules/hermes/profile-manager.nix
    ../../modules/hermes/profile-paseo-project-manager.nix
    ../../modules/hermes/vban-receiver.nix
    ../../modules/hermes/hindsight.nix
  ];

  # The upstream module sets the home to 2770 in both activation and tmpfiles.
  # Gateway discovery requires the control home to be writable only by its owner.
  system.activationScripts.hermes-private-control-home = {
    deps = [ "hermes-agent-setup" ];
    text = ''
      chmod go-w ${lib.escapeShellArg hermesHome}
    '';
  };
  systemd.tmpfiles.rules = [ "z ${hermesHome} 2750 - - - -" ];

  # 插件开关（仅此变体需要）
  services.vbanReceiver.enable = true;
  services.vbanReceiver.port = 6981;
}
