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
      hyprland = { layerRules = true; decoration = true; };
      # Nothing opens from pointer position here: no right-edge levels card, no
      # top-edge overview, and none added later. This is a deliberate personal
      # choice, not a default to route around. Keep it false; do not re-enable
      # a hover-opened panel through another option, a local copy of the
      # shell, or an override of the shared module.
      hoverReveal = false;
    };
    # Bridge must keep running after `connect.py proton` pairs it, or IMAP sync
    # dies the moment that CLI session exits.
    services.protonmail-bridge.enable = true;
  };
}
