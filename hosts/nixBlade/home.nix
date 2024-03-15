{ config, lib, pkgs, inputs, ... }:

{
  imports = 
    [
    ../../modules/home-manager/nix-colors.nix
      ../../modules/home-manager/firefox.nix
      ../../modules/home-manager/gnome.nix
      ../../modules/home-manager/ai.nix
      ../../modules/home-manager/zsh.nix
      ../../modules/home-manager/xremap.nix
      ../../modules/home-manager/hyprland.nix
      ../../modules/home-manager/foot.nix
      ../../modules/home-manager/gtk.nix
      ../../modules/home-manager/mpv.nix
../../modules/home-manager/latex.nix
# ../../modules/home-manager/nixvim.nix
      inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ];
  home.username = "greencheetah";
  home.homeDirectory = "/home/greencheetah";


  home.packages = [ #
    pkgs.signal-desktop
    (pkgs.writeShellScriptBin "aiclip" ''
     touch /tmp/aiclip.lock
     (aichat --role test <<< "$(wl-paste)" > /tmp/aiclip.out && sleep 1 && rm /tmp/aiclip.lock) &
     notifID=$(notify-send -p "ANSWER" "EXPLANATION" -t "10000")
     outOld="ANSWER\nEXPLANATION"
     while [ -e /tmp/aiclip.lock ]
     do
     out="""$(cat /tmp/aiclip.out)
     ..."""
     if [ "$out" != "$outOld" ]
     then
     notify-send "--replace-id=$notifID" -t "10000" "$(echo "$out" | head -n 1)" "$(echo "$out" | tail -n +2)"
     outOld="$out"
     fi
     sleep 0.2
     done
     cat /tmp/aiclip.out
     notify-send "--replace-id=$notifID" -t "$(($(wc -w < /tmp/aiclip.out)*250))" "$(head -n 1 /tmp/aiclip.out)" "$(tail -n +2 /tmp/aiclip.out)"
     rm /tmp/aiclip.out
     '')
     pkgs.lunarvim
     pkgs.kitty
     pkgs.piper
     pkgs.wl-clipboard
     pkgs.ripgrep
     pkgs.gnome.gnome-tweaks
     pkgs.python3
     pkgs.bitwarden
     pkgs.speedcrunch
     pkgs.brave
     pkgs.noto-fonts-cjk
     pkgs.zathura
     pkgs.pavucontrol
     pkgs.gpu-screen-recorder-gtk
     pkgs.pass
     pkgs.neofetch
     pkgs.libnotify
     pkgs.polychromatic
     pkgs.fzf
     pkgs.ffmpeg
     pkgs.yt-dlp
     pkgs.mullvad-vpn
     pkgs.jq
     pkgs.r2modman
     (pkgs.nerdfonts.override { fonts = [ "SourceCodePro" "FiraCode" "DroidSansMono" ]; })
     ];
  services.flatpak = {
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
    packages = [ #
      "com.valvesoftware.Steam"
      "com.valvesoftware.Steam.Utility.gamescope"
      "net.lutris.Lutris"
      "net.ankiweb.Anki"
      "com.github.tchx84.Flatseal"
      "org.qbittorrent.qBittorrent"
      "com.github.bajoja.indicator-kdeconnect"
      "org.prismlauncher.PrismLauncher"
    ];
    overrides = {
      global = {
# Force Wayland by default
        Context = {
          # sockets = ["wayland" "!x11" "!fallback-x11"];
          filesystems = [
            "xdg-data/themes:ro"
          ];
        };

        Environment = {
# Fix un-themed cursor in some Wayland apps
          XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";

# Force correct theme for some GTK apps
          GTK_THEME = "Adwaita:dark";
        };
      };
      "com.valvesoftware.Steam"= {
        Context = {
          filesystems = [
            "xdg-config/r2modmanPlus-local:rw"
          ];
          device = [
            "dri"
          ];
        };
# Environment = {
#   STEAM_FORCE_DESKTOPUI_SCALING = "2.0";
# };
      };
    };
  };

# Home Manager is pretty good at managing dotfiles. The primary way to manage
# plain files is through 'home.file'.
  home.file = {
# # Building this configuration will create a copy of 'dotfiles/screenrc' in
# # the Nix store. Activating the configuration will then make '~/.screenrc' a
# # symlink to the Nix store copy.
# ".screenrc".source = dotfiles/screenrc;

# # You can also set the file content immediately.
# ".gradle/gradle.properties".text = ''
#   org.gradle.console=verbose
#   org.gradle.daemon.idletimeout=3600000
# '';
  };

# Home Manager can also manage your environment variables through
# 'home.sessionVariables'. If you don't want to manage your shell through Home
# Manager then you have to manually source 'hm-session-vars.sh' located at
# either
#
#  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
#
# or
#
#  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
#
# or
#
#  /etc/profiles/per-user/greencheetah/etc/profile.d/hm-session-vars.sh
#
  home.sessionVariables = {
    EDITOR = "lvim";
  };

  programs.home-manager.enable = true;
  home.stateVersion = "23.11"; # Please read the comment before changing.
    services.gnome-keyring.enable = true;

  programs.gpg.enable = true;
  # services.gnupg.agent = {
  #   enable = true;
  #   pinentryPackage = "pkgs.pinentry-gnome3";
  # };
  programs.password-store.enable = true;
}
