{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./brave.nix
    ./browser.nix
    ./composal.nix
    ./firefox.nix
    ./foot.nix
    ./grail.nix
    ./kitty.nix
    ./mpv.nix
    ./ridge.nix
    ./startpage.nix
    ./zathura.nix
  ];
  config = lib.mkIf config.desktop.enable {
    brave.enable = lib.mkDefault true;
    browser.enable = lib.mkDefault true;
    ridge.enable = lib.mkIf osConfig.services.fprintd.enable (lib.mkDefault true);
    home.packages = with pkgs; [
      bitwarden-desktop
      (lib.mkIf osConfig.services.pipewire.enable crosspipe)
      (lib.mkIf osConfig.services.pipewire.pulse.enable pavucontrol)
    ];
    programs = {
      librewolf.enable = lib.mkDefault true;
      qutebrowser.enable = lib.mkDefault true;
      foot.enable = lib.mkDefault true;
      kitty.enable = lib.mkDefault true;
      zathura.enable = lib.mkDefault true;
      mpv.enable = lib.mkIf config.media.enable (lib.mkDefault true);
    };
  };
}
