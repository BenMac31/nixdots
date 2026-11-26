{ config, lib, pkgs, ... }:

{
  options.composal.enable = lib.mkEnableOption "Composal Desktop for Sparks";

  config = lib.mkIf (config.desktop.enable && config.composal.enable) {
    home.packages = [ (pkgs.unfree.callPackage ../../../../pkgs/composal-desktop.nix { }) ];
    xdg.mimeApps.defaultApplications."x-scheme-handler/composal" = "composal-desktop.desktop";
  };
}
