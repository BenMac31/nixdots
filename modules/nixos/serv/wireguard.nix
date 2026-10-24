{ config, lib, pkgs, ... }:
let
  configFile = "/home/oldRoot/etc/wireguard/wg0.conf";
in
{
  options.serv.wireguard.enable = lib.mkEnableOption "Enable WireGuard";
  config = lib.mkIf config.serv.wireguard.enable
    {
      networking.wg-quick.interfaces.wg0.configFile = configFile;
      # tmpfiles ages the copy out of the unit's private /tmp after 10 days,
      # and wg-quick down needs it, or every restart fails on "wg0 already exists".
      systemd.services.wg-quick-wg0.preStop = lib.mkBefore "cp ${configFile} /tmp/wg0.conf";
      networking.firewall.allowedUDPPorts = [ 51820 ];
    };
}
