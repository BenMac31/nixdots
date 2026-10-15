# Tailscale client. Log in once per machine with `sudo tailscale up`: the auth
# key is a secret and stays out of this repo, and the node state in
# /var/lib/tailscale survives rebuilds.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  withMullvad = config.services.mullvad-vpn.enable;

  # Mullvad's routing rules go ahead of Tailscale's and its kill switch drops
  # tailnet traffic. These set the two marks its split tunnelling honours: ct
  # mark 0xf41 passes its firewall, fwmark 0x6d6f6c65 skips its routing table.
  # Priority -125 sits after the mangle hook where Tailscale saves its bits into
  # the ct mark, and before Mullvad's chains, which compare it exactly.
  # 100.64.0.0/24 is Mullvad's DNS. So the tailnet bypasses Mullvad, and a
  # Tailscale exit node cannot be used while Mullvad is connected.
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
      # The tunnel port, so peers connect directly instead of through DERP.
      openFirewall = true;
      # Exit nodes need "client", which loosens reverse-path filtering.
      useRoutingFeatures = "none";
    };

    # The tailnet reaches every service here without a port opened to the LAN.
    networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];

    # Without resolved, tailscaled owns /etc/resolv.conf and reads the network's
    # resolvers once per link change. On fresh wifi that is before NetworkManager
    # has written them, and every lookup SERVFAILs until `tailscale down && up`.
    # With resolved each link keeps its own. LLMNR, mDNS and the fallback
    # servers are off so lookups behave as they did under glibc.
    services.resolved = {
      enable = true;
      settings.Resolve = {
        LLMNR = false;
        MulticastDNS = false;
        FallbackDNS = "";
      };
      # XiaServer is shared in from Dan's tailnet, so it answers only to its full
      # name; searching his suffix makes the bare `xiaserver` that agents print
      # resolve. A delegate because tailscaled rewrites tailscale0's domains, and
      # resolved's global search list needs a global resolver.
      dnsDelegates.shared-tailnet.Delegate = {
        DNS = "100.100.100.100";
        Domains = "tail028f45.ts.net";
      };
    };

    # With Mullvad's rule first, the route back to a tailnet peer is looked up
    # in Mullvad's table, which names its tunnel, not the arriving interface.
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
