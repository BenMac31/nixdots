{ lib, config, pkgs, ... }:
{
  options = {
    ai.reason = {
      enable = lib.mkEnableOption "the Reason Machines CLI and desktop app";
    };
  };
  config = lib.mkIf config.ai.reason.enable {
    home.packages = [
      (pkgs.unfree.callPackage ../../../../pkgs/reason-cli.nix { })
      (pkgs.unfree.callPackage ../../../../pkgs/reason-desktop.nix { })
    ];
    # The app refuses to sign in unless it owns these schemes, and cannot
    # register itself because mimeapps.list is read-only.
    xdg.mimeApps.defaultApplications = {
      "x-scheme-handler/reason" = "reason-desktop.desktop";
      "x-scheme-handler/ara" = "reason-desktop.desktop";
    };
  };
}
