# hosts/raiyun/default.nix — 雨云 VPS 最小变体
# 带 mihomo 代理服务（首次启动后上传配置到 /opt/mihomo/ 即可) 
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

  # 初始 root 密码（首次登录后立刻改掉，rebuild 不会覆盖）
  users.users.root.initialPassword = "nixos";

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
