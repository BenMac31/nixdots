{ config, lib, pkgs, inputs, ... }:

{
  wayland.windowManager.hyprland.settings = {
    monitor= "eDP-1,2560x1440@48.01Hz,auto,2";
    animations.enabled = false;
    unbind = [
    "SUPER,SUPER_L"
    ];
  };

  programs.mpv.config.profile = "fast";
}
