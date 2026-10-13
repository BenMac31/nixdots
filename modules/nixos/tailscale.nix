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
# DNS runs through systemd-resolved. Without it tailscaled falls back to
# openresolv, takes /etc/resolv.conf for itself and forwards every lookup that
# is not for the tailnet to whatever resolvers the network had the last time
# it looked. It looks once per link change, in the same second the new address
# appears, and on a fresh wifi network that is before NetworkManager has
# written the new resolvers: the list comes back empty, every lookup returns
# SERVFAIL, and nothing asks again until `tailscale down && tailscale up`.
# With resolved each link keeps its own resolvers. NetworkManager updates the
# wifi link, Tailscale claims only ts.net on tailscale0, and Mullvad claims
# everything else on its tunnel while it is connected. LLMNR, mDNS and the
# compiled-in fallback resolvers are off so that names resolve the way they
# did under glibc: unicast DNS to the resolvers the network handed out.
#
# XiaServer (and whatever else Dan shares) lives on Dan's tailnet and is only
# shared into this one. MagicDNS searches this tailnet's own suffix, so a
# shared node answers only to its full name, xiaserver.tail028f45.ts.net.
# Searching Dan's suffix too makes the bare `xiaserver` that the artifact
# store, its publish script and every link an agent prints resolve here the
# same as on Dan's machines. A delegate rather than a search domain on a link
# or in resolved.conf: tailscaled rewrites tailscale0's domains whenever its
# config changes, and resolved's global search list only applies to global
# resolvers, of which there are none. The delegate carries the suffix and
# MagicDNS's address together, so it holds whichever links are up.
#
# Mullvad (services.mullvad-vpn, on the hosts that enable it) and Tailscale
# both want the routing table and the firewall. Connecting Mullvad puts its
# routing rules ahead of Tailscale's, so packets for the tailnet leave through
# the Mullvad tunnel and die there, and its kill switch drops whatever still
# finds tailscale0 or leaves tailscaled for the wifi. The mullvad-tailscale
# table gives tailnet traffic and tailscaled's own the two marks Mullvad's
# split tunnelling honours: conntrack mark 0xf41 passes its firewall, fwmark
# 0x6d6f6c65 skips its routing table. The output chain sits after iptables'
# mangle hook, where Tailscale saves its own bits into the conntrack mark, and
# before Mullvad's filter chains, which compare that mark exactly.
# 100.64.0.0/24 is cut out of the tailnet range because Mullvad's
# content-blocking resolvers live there. Reverse-path filtering goes loose
# because, with Mullvad's rule first, the route back to a tailnet peer or a
# DERP server is looked up in Mullvad's table, which names the tunnel and not
# the interface the packet arrived on. The price: the tailnet and tailscaled
# go around Mullvad, so peers and Tailscale's servers see the real address,
# and a Tailscale exit node cannot be combined with a connected Mullvad.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  withMullvad = config.services.mullvad-vpn.enable;

  mullvadBypass = pkgs.writeText "mullvad-tailscale.nft" ''
    table inet mullvad-tailscale
    delete table inet mullvad-tailscale
    table inet mullvad-tailscale {
      chain output {
        type route hook output priority -125; policy accept;
        ip daddr 100.64.0.0/10 ip daddr != 100.64.0.0/24 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
        ip6 daddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
        meta mark & 0x00ff0000 == 0x00080000 oifname "wg0-mullvad" ct mark set 0x00000f41 meta mark set 0x6d6f6c65
        meta mark & 0x00ff0000 == 0x00080000 ct mark set 0x00000f41
      }
      chain input {
        type filter hook input priority -100; policy accept;
        iifname "${config.services.tailscale.interfaceName}" ct mark set 0x00000f41
      }
    }
  '';
in
{
  options.custom.tailscale.enable = lib.mkEnableOption "the Tailscale client daemon";

  config = lib.mkIf config.custom.tailscale.enable {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "none";
    };

    networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];

    services.resolved = {
      enable = true;
      settings.Resolve = {
        LLMNR = false;
        MulticastDNS = false;
        FallbackDNS = "";
      };
      dnsDelegates.shared-tailnet.Delegate = {
        DNS = "100.100.100.100";
        Domains = "tail028f45.ts.net";
      };
    };

    networking.firewall.checkReversePath = lib.mkIf withMullvad "loose";

    systemd.services.mullvad-tailscale = lib.mkIf withMullvad {
      description = "Firewall marks that carry the tailnet around Mullvad";
      wantedBy = [ "multi-user.target" ];
      before = [
        "mullvad-daemon.service"
        "tailscaled.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.nftables}/bin/nft -f ${mullvadBypass}";
        ExecStop = "${pkgs.nftables}/bin/nft delete table inet mullvad-tailscale";
      };
    };
  };
}
