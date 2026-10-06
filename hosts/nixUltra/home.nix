{ lib, ... }:

{
  imports = [ ../nixBlade/home.nix ];

  # The 2880x1800 OLED: 1.6 is the nearest scale Hyprland accepts (1800x1125
  # logical); nixBlade's 1.56667 is not a whole-pixel divisor here.
  wayland.windowManager.hyprland.settings.monitor = lib.mkForce [
    ",preferred,auto,1.6"
    "DP-2,preferred,auto,1.6"
  ];
}
