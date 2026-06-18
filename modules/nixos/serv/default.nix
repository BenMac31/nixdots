{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports = [
    ./home-assistant.nix
    ./media.nix
    ./minecraft.nix
    ./wireguard.nix
  ];
  options.serv.enable = lib.mkEnableOption "Enable the serv module";
  config = lib.mkIf config.serv.enable
    {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = lib.mkDefault false;
          UseDns = true;
          PermitRootLogin = "no"; # "yes", "without-password", "prohibit-password", "forced-commands-only", "no"
        };
      };
    };
}
