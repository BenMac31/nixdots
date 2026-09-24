{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports = [
    ./plymouth.nix
    ./sddm.nix
  ];
  options.head.enable = lib.mkEnableOption "Set if headed system";
  options.head.gaming = lib.mkEnableOption "Enable gaming";
  config = lib.mkIf config.head.enable {
    boot.plymouth.enable = lib.mkDefault true;
    services = {
      displayManager.sddm.enable = lib.mkDefault true;
      pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };
    };
    hardware.pulseaudio.enable = false;
    # home-manager can't write /etc/pam.d. fprintAuth off so typing a password
    # never waits on the reader; hyprlock talks to fprintd directly instead.
    security.pam.services.hyprlock = lib.mkIf config.programs.hyprland.enable {
      fprintAuth = false;
    };
    programs = lib.mkIf config.head.gaming {
      gamemode.enable = true;
      gamescope.enable = true;
    };
    fonts.fontDir.enable = true;
    hardware.uinput.enable = lib.mkIf config.head.gaming true;
  };
}
