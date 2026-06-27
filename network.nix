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
