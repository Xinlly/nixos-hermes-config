# hosts/wsl/easytier.nix — EasyTier 客户端实例（WSL 工作站加入 xavier-mesh）
# 主动连 raiyun2 公网入口；不做公共中继。网络密钥经 EnvironmentFile 注入，不入 store。
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
      peers = [ "tcp://ry.xinlly.top:51010" ];
    };
    environmentFiles = [ "/var/lib/hermes/.easytier/client.env" ];
  };
}
