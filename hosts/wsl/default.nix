# hosts/wsl/default.nix — WSL2 变体：Hermes 全功能开发工作站
#
# 变体身份常量 + 模块聚合。新增云服务器变体时复制此文件改名即可。
{ config, lib, pkgs, ... }:
{
  imports = [
    ../../common/base.nix
    ../../common/proxy.nix
    ./users.nix
    ./hermes.nix
  ];

  # ══ 主机身份 ══
  networking.hostName = "nixos";
  system.stateVersion = "26.05";

  # WSL2 特性
  wsl.enable = true;
  wsl.defaultUser = "xavier";

  # Podman 容器运行时
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # WSL2 独有工具（Node.js、GitHub CLI）
  environment.systemPackages = with pkgs; [ nodejs_22 gh ];

  # Mihomo 代理 — 极简 systemd 服务
  # 不用 nixpkgs services.mihomo，避免 PrivateUsers/DynamicUser 沙箱冲突
  systemd.services.mihomo = {
    description = "Mihomo Proxy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "hermes";
      Group = "hermes";
      WorkingDirectory = "/var/lib/hermes/workspace/projects/our/mihomo";
      ExecStart = "${pkgs.mihomo}/bin/mihomo -d /var/lib/hermes/workspace/projects/our/mihomo -f /var/lib/hermes/workspace/projects/our/mihomo/config.yaml";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
