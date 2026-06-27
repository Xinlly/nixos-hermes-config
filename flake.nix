# flake.nix — Nix Flake 入口，声明所有输入源和系统配置模块
{
  inputs = {
    # NixOS 官方 nixpkgs，跟随 unstable 分支
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # WSL2 适配层
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    # Hermes Agent 发行版，锁定 0.17.0 版本（无版本 tag，用 commit SHA）
    hermes-agent.url = "github:NousResearch/hermes-agent/857d0244af8498046c9c796e0a82bbc2fef79368";
    # 飞书流式卡片侧车，来自本地 git 仓库（非 flake，需 flake=false）
    hermes-feishu-card.url = "path:/var/lib/hermes/workspace/projects/our/hermes-feishu-streaming-card";
    hermes-feishu-card.flake = false;
  };

  outputs = { self, nixpkgs, nixos-wsl, hermes-agent, ... }@inputs: {
    # 唯一的 NixOS 系统配置：主机名 nixos，x86_64 架构
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };  # 所有 flake input 传给模块
      modules = [
        nixos-wsl.nixosModules.default      # WSL2 支持
        hermes-agent.nixosModules.default   # Hermes 服务及 CLI
        ./configuration.nix                 # NixOS 基础配置
        ./network.nix                       # 网络接口配置
        ./proxy.nix                         # 系统代理 shell 函数
        ./users.nix                         # 用户 & sudo 权限
        ./hermes.nix                        # Hermes Agent 核心配置（含 portaudio 本地编译）
        ./hindsight.nix                     # Hindsight 记忆引擎
        ./modules/feishu-card.nix           # 飞书流式卡片模块
        ./modules/vban-receiver.nix         # VBAN 音频接收器模块
      ];
    };
  };
}
