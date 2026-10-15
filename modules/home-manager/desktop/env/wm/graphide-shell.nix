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
    };
    # Bridge must keep running after `connect.py proton` pairs it, or IMAP sync
    # dies the moment that CLI session exits.
    services.protonmail-bridge.enable = true;
  };
}
