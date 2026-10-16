{ config, lib, pkgs, inputs, ... }:
{
  imports = [ inputs.graphide-tools.homeManagerModules.quickshell ];
  config = lib.mkIf config.programs.graphide-shell.enable {
    programs.graphide-shell = {
      widgetMonitor = "eDP-1";
      terminalPackage = pkgs.kitty;
      pomodoro = pkgs.waybar-pomodoro;
      rbwPinentry = true;
      todoCommand = [ "nvim" "${config.home.homeDirectory}/Projects/graphide/docs/TODO.md" ];
      commitsRepo = "${config.home.homeDirectory}/Projects/graphide/graphide";
      hyprland = { layerRules = true; decoration = true; };
      # No panel opens from pointer position, by choice. Keep it that way.
      hoverReveal = false;
      launcherSideCards = false;
      # The panel's mode, so the plates are drawn at its own resolution.
      layout = { width = 2880; height = 1800; scale = 1.6; };
      plates = {
        enable = true;
        place = { name = "San Francisco"; latitude = 37.7749; longitude = -122.4194; };
      };
      # Held on XiaServer, so Dan can add to the list too: `remind ben "..."`.
      serverReminders = {
        person = "ben";
        addTo = [ "ben" "dan" ];
      };
    };
    # Bridge must keep running after `connect.py proton` pairs it, or IMAP sync
    # dies the moment that CLI session exits.
    services.protonmail-bridge.enable = true;
  };
}
