{ lib, config, pkgs, ... }:
{
  options = {
    sync = {
      enable = lib.mkEnableOption "Enable sync";
    };
  };
  config = lib.mkIf config.sync.enable {
    home.packages = [
      pkgs.blueman
    ];
    services.kdeconnect = {
      enable = true;
      indicator = true;
    };
  };
}
