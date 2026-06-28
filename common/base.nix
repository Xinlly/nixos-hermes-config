# common/base.nix — 所有变体共享的基础配置
#
# WSL 特定配置、Hermes 等移到 hosts/<name>/ 下。
{ config, pkgs, ... }:
{
  # Nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  programs.nix-ld.enable = true;

  # 基础工具（所有主机通用）
  environment.systemPackages = with pkgs; [ git vim wget ];

  # Podman 容器运行时
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
}
