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

  # nix 源用清华镜像 + fallback 到官方源
  nix.settings.substituters = [
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    "https://cache.nixos.org/"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];

  # 限制编译时CPU使用
  nix.settings.max-jobs = 4;
  nix.settings.cores = 4;

  # WSL2 特性
  wsl.enable = true;
  wsl.defaultUser = "xavier";

  # WSL Interop — 隔离 Windows PATH + 持久化 binfmt 注册
  wsl.interop.register = true;                          # 显式注册 binfmt，允许执行 .exe
  wsl.interop.includePath = false;                       # NixOS 不注入 Windows 路径到 PATH
  wsl.wslConf.interop.appendWindowsPath = false;         # WSL 也不注入 Windows 路径

  # Podman 容器运行时
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # WSL2 独有工具（Node.js、GitHub CLI、飞书 CLI）
  environment.systemPackages = with pkgs; [ nodejs_22 gh feishu-cli ];

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
