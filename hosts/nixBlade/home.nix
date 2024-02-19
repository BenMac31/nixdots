{ config, pkgs, inputs, ... }:

{
  imports = 
    [
    ../../modules/home-manager/firefox.nix
      ../../modules/home-manager/gnome.nix
      ../../modules/home-manager/ai.nix
      ../../modules/home-manager/zsh.nix
# ../../modules/home-manager/nixvim.nix
      inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ];
  home.username = "greencheetah";
  home.homeDirectory = "/home/greencheetah";


  home.packages = with pkgs; [ #
    signal-desktop
    lunarvim
    foot
    kitty
    wl-clipboard
    ripgrep
    noto-fonts-cjk
    pavucontrol
    pass

# # It is sometimes useful to fine-tune packages, for example, by applying
# # overrides. You can do that directly here, just don't forget the
# # parentheses. Maybe you want to install Nerd Fonts with a limited number of
# # fonts?
# (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

# # You can also create simple shell scripts directly inside your
# # configuration. For example, this adds a command 'my-hello' to your
# # environment:
# (pkgs.writeShellScriptBin "my-hello" ''
#   echo "Hello, ${config.home.username}!"
# '')
    ];
# home.packages = with uPkgs; [
#   r2modman
# ];
  services.flatpak = {
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
    packages = [ #
      "com.valvesoftware.Steam"
      "net.ankiweb.Anki"
      "org.qbittorrent.qBittorrent"
    ];
    overrides = {
      "com.valvesoftware.Steam"= {
        Context.filesystems = [
          "xdg-config/r2modmanPlus-local"
        ];
        Environment = {
          STEAM_FORCE_DESKTOPUI_SCALING = "2.0";
        };
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
  services.gpg-agent = {
    enable = true;
    pinentryFlavor = "gnome3";
  };
  programs.password-store.enable = true;
}
