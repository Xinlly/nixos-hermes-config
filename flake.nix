# flake.nix — Nix Flake 入口，声明所有输入源和系统配置模块
# v0.4.0: 模块化 — hosts/<name>/ 变体模式，支持多机部署
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
    # llm-agents.nix — AI 编码代理软件包（含 agent-browser CLI）
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, nixos-wsl, hermes-agent, ... }@inputs: {
    # ── 变体：WSL2 Hermes 全功能开发工作站 ──
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        nixos-wsl.nixosModules.default
        hermes-agent.nixosModules.default
        ./hosts/wsl/default.nix
        # 以上模块已通过 imports 链式引入所有子模块：
        #   hosts/wsl/default.nix → common/* + users + hermes
        #   hosts/wsl/hermes.nix  → modules/hermes/*
      ];
    };

    # ── 变体：雨云 VPS（mihomo 代理，无 Hermes）──
    # nixosConfigurations.raiyun = nixpkgs.lib.nixosSystem {
    #   system = "x86_64-linux";
    #   specialArgs = { inherit inputs; };
    #   modules = [
    #     ./hosts/raiyun/default.nix
    #   ];
    # };
  };
}
