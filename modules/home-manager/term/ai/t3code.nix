{ lib, config, pkgs, ... }:
{
  options = {
    ai.t3code = {
      enable = lib.mkEnableOption "the T3 Code desktop app";
    };
  };
  config = lib.mkIf config.ai.t3code.enable {
    home.packages = [ (pkgs.callPackage ../../../../pkgs/t3code.nix { }) ];
    xdg.mimeApps.defaultApplications = {
      "x-scheme-handler/t3code" = "t3code.desktop";
    };
  };
}
