# hosts/raiyun2/default.nix — 新机 rainyun2（雨云高速线路）
# 目标：最小 NixOS + SSH。暂不含 Tailscale/DERP/mihomo。
# KVM 部署：GPT + disko，网络按 virtio 驱动匹配
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    ../../common/base.nix
    ./disk-config.nix
    (modulesPath + "/profiles/qemu-guest.nix")  # virtio 驱动（网络/磁盘/balloon）
  ];

  # ══ 主机身份 ══
  networking.hostName = "raiyun2";
  system.stateVersion = "26.05";

  # nix 源用清华镜像
  nix.settings.substituters = [ "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" ];
  nix.settings.trusted-substituters = [ "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" ];

  # 静态 IP — systemd.network 按驱动匹配（MAC 会变，virtio_net 驱动不变）
  networking.useDHCP = false;
  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.Driver = "virtio_net";
    networkConfig.DHCP = "no";
    address = [ "172.16.71.87/16" ];
    routes = [
      { routeConfig = { Gateway = "172.16.0.1"; GatewayOnLink = true; }; }
    ];
  };
  networking.nameservers = [ "223.5.5.5" ];

  # GPT + BIOS 引导，GRUB 由 disko 自动生成
  boot.loader.grub.enable = true;

  # SSH 远程管理
  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };

  # 防火墙 — 放行 SSH
  networking.firewall.allowedTCPPorts = [ 22 ];

  # 初始 root 密码（首次登录后立刻改掉，rebuild 不会覆盖）
  users.users.root.initialPassword = "nixos";
  # SSH 公钥认证（免密码登录）
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM/bIU/pfKrNm20nW3pjzEsBqlK9XOWdaia6gCPVt3oe raiyun-nixos"
  ];
}
