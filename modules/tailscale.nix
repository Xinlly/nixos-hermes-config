# modules/tailscale.nix — Tailscale VPN
#
# 按需导入：raiyun 等需要 Tailscale 的主机在 imports 中引用
# WSL2 mirrored 模式不导入（宿主机 Tailscale 已覆盖）
{ config, ... }:
{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  services.resolved.enable = true;

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
  };
}
