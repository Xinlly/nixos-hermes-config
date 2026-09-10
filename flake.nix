# flake.nix — Nix Flake 入口，声明所有输入源和系统配置模块
# v0.4.0: 模块化 — hosts/<name>/ 变体模式，支持多机部署
{
  inputs = {
    # NixOS 官方 nixpkgs，跟随 unstable 分支
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # WSL2 适配层
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    # Hermes Agent 发行版（v0.20.1 / 2026.8.13）
    hermes-agent.url = "github:NousResearch/hermes-agent/v2026.8.13";
    # llm-agents.nix — AI 编码代理软件包（含 agent-browser CLI）
    llm-agents.url = "github:numtide/llm-agents.nix";
    # Paseo — 多 coding agent 编排 daemon（官方 flake，含 NixOS 模块与包）
    # pin 到已本地构建验证的 0.8.0-beta.1 commit，避免 main 漂移
    paseo.url = "github:getpaseo/paseo/da8c1b5c94e752b01d451645e5fa52aba2c1b2f0";
    paseo.inputs.nixpkgs.follows = "nixpkgs";
    # Aowen-Nowor hermes-lark-streaming 插件（目录插件，非 flake）
    hermes-lark-streaming-aowen.url = "github:Aowen-Nowor/hermes-lark-streaming";
    hermes-lark-streaming-aowen.flake = false;
    # Xinlly/skills 中经审核的 Matt workflow Hermes 插件（目录插件，非 flake）
    matt-workflows.url = "github:Xinlly/skills/37f135c";
    matt-workflows.flake = false;
    # disko — 声明式分区
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    # nixos-anywhere — 远程安装工具（复用 nixpkgs 缓存避免重复下载）
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-wsl, hermes-agent, disko, nixos-anywhere, ... }@inputs: {
    # ── 变体：WSL2 Hermes 全功能开发工作站 ──
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        nixos-wsl.nixosModules.default
        hermes-agent.nixosModules.default
        inputs.paseo.nixosModules.default
        ./hosts/wsl/default.nix
        # 以上模块已通过 imports 链式引入所有子模块：
        #   hosts/wsl/default.nix → common/* + users + hermes
        #   hosts/wsl/hermes.nix  → modules/hermes/*
      ];
    };

    # ── 变体：雨云 VPS（最小 NixOS，手动运行 mihomo）──
    nixosConfigurations.raiyun = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        ./hosts/raiyun/default.nix
      ];
    };

    packages.x86_64-linux.nixos-anywhere = nixos-anywhere.packages.x86_64-linux.default;
  };
}
