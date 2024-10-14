{ config, lib, pkgs, inputs, ... }:

{
  imports = [ #
    ../../modules/home-manager/nix-colors.nix
    ../../modules/home-manager/firefox.nix
    ../../modules/home-manager/gnome.nix
    ../../modules/home-manager/ai.nix
    ../../modules/home-manager/zsh.nix
    ../../modules/home-manager/hyprland.nix
    ../../modules/home-manager/foot.nix
    ../../modules/home-manager/zathura.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/mpv.nix
    ../../modules/home-manager/xdg.nix
    ../../modules/home-manager/gaming.nix
    ../../modules/home-manager/latex.nix
    ../../modules/home-manager/vim.nix
    ../../modules/home-manager/japanese.nix
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  home.username = "greencheetah";
  home.homeDirectory = "/home/greencheetah";


  home.packages = [ #
    pkgs.signal-desktop
    pkgs.element-desktop
    pkgs.kitty
    # pkgs.unfree.android-studio
    pkgs.piper
    pkgs.wl-clipboard
    pkgs.R
    pkgs.ripgrep
    pkgs.gnome.gnome-tweaks
    pkgs.bitwarden
    pkgs.rbw
    pkgs.speedcrunch
    pkgs.pavucontrol
    pkgs.gpu-screen-recorder-gtk
    pkgs.pass
    pkgs.neofetch
    pkgs.libnotify
    pkgs.polychromatic
    pkgs.fzf
    pkgs.unfree.ffmpeg-full
    pkgs.yt-dlp
    pkgs.mullvad-vpn
    pkgs.jq
    (pkgs.nerdfonts.override { fonts = [ "SourceCodePro" "FiraCode" "DroidSansMono" ]; })
    pkgs.sxiv
    pkgs.libsixel
    pkgs.imagemagick
    pkgs.newsboat
    pkgs.unfree.ytfzf
    pkgs.nix-output-monitor
    pkgs.thunderbird
    ];
  services.flatpak = {
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
    packages = [ #
      "net.ankiweb.Anki"
      "com.github.tchx84.Flatseal"
      "org.qbittorrent.qBittorrent"
      "com.github.bajoja.indicator-kdeconnect"
    ];
    overrides = {
      global = {
        Context = {
        filesystems = [
        "xdg-config/gtk-4.0"
        "xdg-config/gtk-3.0"
        "${pkgs.gruvbox-gtk-theme}/share/themes/"
        "xdg-config/themes/"
        ];
        };

        Environment = {
          XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
          GTK_THEME = "Gruvbox-Dark-BL";
        };
      };
    };
  };

  programs.home-manager.enable = true;
  home.stateVersion = "23.11"; # Do not change
    services.gnome-keyring.enable = true;

  programs = {
  gpg.enable = true;
  password-store.enable = true;
  };
}
