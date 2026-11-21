# hosts/wsl/easytier.nix — EasyTier 客户端实例（WSL 工作站加入 xavier-mesh）
# 主动连 xavier-mesh 公共节点公网入口 cn.xinlly.top:17017（雨云 DNAT → raiyun 内网 11010）；
# 本机纯客户端，不做公共中继。网络密钥经 EnvironmentFile 注入，不入 store。
{ ... }:
{
  services.easytier.enable = true;
  services.easytier.instances.wsl = {
    enable = true;
    settings = {
      network_name = "xavier-mesh";
      hostname = "nixos-wsl";
      dhcp = true;                  # 动态分配虚拟网 IPv4（DHCP），不再写死 10.144.144.20
      listeners = [];               # 纯客户端，不做监听
      peers = [ "tcp://cn.xinlly.top:17017" ];
    };
    environmentFiles = [ "/var/lib/hermes/.easytier/client.env" ];
  };
}
