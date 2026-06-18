{ config, lib, pkgs, ... }:
{
  options.serv.wireguard.enable = lib.mkEnableOption "Enable WireGuard";
  config = lib.mkIf config.serv.wireguard.enable
    {
      networking.wg-quick.interfaces.wg0.configFile = "/home/oldRoot/etc/wireguard/wg0.conf";
      networking.firewall.allowedUDPPorts = [ 51820 ];
    };
}
