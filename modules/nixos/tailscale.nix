# Tailscale client daemon.
#
# The daemon is declarative; the tailnet login is not. An auth key is a secret
# and this repo is not the place for one, so nothing here logs the machine in.
# After the first rebuild, run `sudo tailscale up` once and follow the printed
# browser link. Node state lives in /var/lib/tailscale and survives rebuilds
# and upgrades, so that is one step per machine, not one per deploy.
#
# openFirewall opens UDP 41641, the tunnel port, so peers can reach this node
# directly instead of relaying every packet through a DERP server. tailscaled
# drops anything that is not WireGuard-authenticated, so the exposure is the
# same as any other WireGuard endpoint.
#
# trustedInterfaces accepts whatever arrives on tailscale0 without consulting
# the port lists in ./default.nix. That is the point of the tailnet: sshd and
# anything else on this box stay reachable from your own devices without a
# single port being opened to the LAN or the internet.
#
# useRoutingFeatures stays "none" -- this node neither advertises routes nor
# rides an exit node. Set it to "client" before `tailscale up --exit-node=...`;
# that relaxes reverse-path filtering, which exit-node traffic needs, and
# "server"/"both" additionally turns on IP forwarding for a subnet router.
#
# One caveat specific to nixWorks: services.mullvad-vpn is enabled here, and
# Mullvad and Tailscale both want to own routing and DNS. With the Mullvad
# tunnel up its kill switch can swallow tailnet traffic. If the tailnet goes
# dark only while Mullvad is connected, that is the cause, not this module.
{ config, lib, ... }:
{
  options.custom.tailscale.enable = lib.mkEnableOption "the Tailscale client daemon";

  config = lib.mkIf config.custom.tailscale.enable {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "none";
    };

    networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
  };
}
