# hosts/raiyun/easytier.nix — EasyTier 公共节点（独立网络 xavier-mesh，与 Tailscale DERP 共存）
# 公网接入：雨云控制台 TCP DNAT 51010 -> 本机 11010
# 网络密码：由主机 /var/lib/easytier/relay.env 的 ET_NETWORK_SECRET 提供
#          （secret 从 raiyun2 复制，Nix 中不出现明文）
# 与 raiyun2 的 xinlly-mesh 靠 network_name 隔离，互不相通。
{ ... }:
{
  services.easytier.enable = true;
  services.easytier.instances.relay = {
    enable = true;
    settings = {
      network_name = "xavier-mesh";
      ipv4 = "10.122.122.1";
      listeners = [ "tcp://0.0.0.0:11010" ];
    };
    environmentFiles = [ "/var/lib/easytier/relay.env" ];
  };

  networking.firewall.allowedTCPPorts = [ 11010 ];
}
