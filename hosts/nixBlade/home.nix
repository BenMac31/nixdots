{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    #
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/ai.nix
    ../../modules/home-manager/zsh.nix
    ../../modules/home-manager/xdg.nix
    ../../modules/home-manager/vim.nix
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  home.username = "greencheetah";
  home.homeDirectory = "/home/greencheetah";
  sync.enable = true;
  gaming.enable = true;


  home.packages = [
    #
    (pkgs.python3.withPackages (python-pkgs: [
      python-pkgs.matplotlib
      python-pkgs.scipy
      python-pkgs.numpy
      python-pkgs.pandas
    ]))
    pkgs.unzip
    pkgs.btop
    # pkgs.unfree.android-studio
    pkgs.R
    pkgs.ripgrep
    pkgs.rbw
    pkgs.fastfetch
    pkgs.libnotify
    pkgs.fzf
    pkgs.yt-dlp
    pkgs.mullvad-vpn
    pkgs.jq
    (pkgs.nerdfonts.override { fonts = [ "SourceCodePro" "FiraCode" "DroidSansMono" ]; })
    pkgs.sxiv
    pkgs.libsixel
    pkgs.newsboat
    pkgs.nix-output-monitor
    pkgs.fractal
  ];

  services.flatpak.update.onActivation = true;

  programs.home-manager.enable = true;
  home.stateVersion = "23.11"; # Do not change

  programs = {
    gpg.enable = true;
    password-store.enable = true;
    rbw.settings.pinentry = pkgs.pinentry-gnome3;
  };
  systemd.user.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh"; # Makes ssh-agent work
}
