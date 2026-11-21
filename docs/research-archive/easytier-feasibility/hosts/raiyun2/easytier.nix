# hosts/raiyun2/easytier.nix — EasyTier 公共节点（与 Tailscale DERP 共存）
# 公网接入：雨云控制台 TCP DNAT 51010 -> 本机 11010
# 网络密码：由主机 /var/lib/easytier/relay.env 的 ET_NETWORK_SECRET 提供
#          （xavier 生成，Nix 中不出现明文）
{ ... }:
{
  services.easytier.enable = true;
  services.easytier.instances.relay = {
    enable = true;
    settings = {
      network_name = "xinlly-mesh";
      ipv4 = "10.144.144.1";
      listeners = [ "tcp://0.0.0.0:11010" ];
    };
    environmentFiles = [ "/var/lib/easytier/relay.env" ];
  };

  networking.firewall.allowedTCPPorts = [ 11010 ];
}
