# hosts/raiyun/default.nix — 雨云 VPS
# KVM 部署：GPT + disko 分区，按 virtio 驱动匹配网络
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    ../../common/base.nix
    ../../common/network.nix
    ../../common/proxy.nix
    ./disk-config.nix
    ./derper.nix
    (modulesPath + "/profiles/qemu-guest.nix")  # virtio 驱动（磁盘/网络/balloon）
  ];

  # ══ 主机身份 ══
  networking.hostName = "raiyun";
  system.stateVersion = "26.05";

  # nix 源用清华镜像（安装后 rebuild 可改为直连或代理）
  nix.settings.substituters = [ "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" ];
  nix.settings.trusted-substituters = [ "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" ];

  # 静态 IP — systemd.network 按驱动匹配（MAC 重装会变，驱动不变）
  networking.useDHCP = false;
  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.Driver = "virtio_net";
    networkConfig.DHCP = "no";
    address = [ "172.16.0.97/16" ];
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

  # Mihomo 代理 — 二进制来自 nixpkgs，配置手动上传
  # 首次启动后：SFTP 传 config.yaml + geodata 到 /opt/mihomo/，然后 systemctl restart mihomo
  # 重启上限：5 分钟内最多 3 次，避免缺配置时无限重试
  systemd.tmpfiles.rules = [ "d /opt/mihomo 0755 root root -" ];
  systemd.services.mihomo = {
    description = "Mihomo Proxy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    startLimitBurst = 3;
    startLimitIntervalSec = 300;
    serviceConfig = {
      User = "root";
      WorkingDirectory = "/opt/mihomo";
      ExecStart = "${pkgs.mihomo}/bin/mihomo -d /opt/mihomo -f /opt/mihomo/config.yaml";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
