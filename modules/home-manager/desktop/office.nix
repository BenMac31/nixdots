{ lib, config, pkgs, ... }:
{
  options = {
    office = {
      enable = lib.mkEnableOption "Enable office";
    };
  };
  config = lib.mkIf config.office.enable {
    home.packages = with pkgs; [
      speedcrunch
      zathura
      texliveFull
      libreoffice-qt
      hunspell
      pkgs.anki-bin
    ];
  };
}
