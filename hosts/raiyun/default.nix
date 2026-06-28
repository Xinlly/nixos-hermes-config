# hosts/raiyun/default.nix — 雨云 VPS 最小变体
# 阶段一：只跑起 NixOS + SSH，手动运行 mihomo
{ config, lib, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ../../common/base.nix
    ../../common/proxy.nix
  ];

  # ══ 主机身份 ══
  networking.hostName = "raiyun";
  system.stateVersion = "26.05";

  # 静态 IP（172.16.0.97/16，网关 172.16.0.1）
  networking.useDHCP = false;
  networking.interfaces.ens18 = {
    ipv4.addresses = [{ address = "172.16.0.97"; prefixLength = 16; }];
  };
  networking.defaultGateway = "172.16.0.1";
  networking.nameservers = [ "223.5.5.5" ];

  # BIOS 引导（设备由 disko 管理）
  boot.loader.grub.enable = true;

  # SSH 远程管理
  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };

  # 防火墙 — 放行 SSH
  networking.firewall.allowedTCPPorts = [ 22 ];
}
