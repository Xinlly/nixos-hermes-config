# hosts/wsl/default.nix — WSL2 变体：Hermes 全功能开发工作站
#
# 变体身份常量 + 模块聚合。新增云服务器变体时复制此文件改名即可。
{ config, lib, pkgs, ... }:
{
  imports = [
    ../../common/base.nix
    ../../common/network.nix
    ../../common/proxy.nix
    ./users.nix
    ./hermes.nix
  ];

  # ══ 主机身份 ══
  networking.hostName = "nixos";
  system.stateVersion = "26.05";

  # WSL2 特性
  wsl.enable = true;
  wsl.defaultUser = "xavier";

  # WSL2 独有工具（Node.js、GitHub CLI）
  environment.systemPackages = with pkgs; [ nodejs_22 gh ];
}
