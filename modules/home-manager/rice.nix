{ pkgs, inputs, config, ... }:
{
  imports = [
    inputs.nix-colors.homeManagerModules.default
  ];
  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-dark-medium;
  gtk = {
    enable = true;
    theme = {
      package = pkgs.gruvbox-gtk-theme;
      name = "Gruvbox-Dark";
    };
    iconTheme = {
      package = pkgs.gruvbox-dark-icons-gtk;
      name = "Oomox-gruvbox-dark";
    };
  };
  xdg.configFile = {
    "Kvantum/gruvbox-kvantum/".source = "${inputs.gruvbox-kvantum}/gruvbox-kvantum/";
    "Kvantum/kvantum.kvconfig".text = "[General]\ntheme=gruvbox-kvantum";
  };
  home.sessionVariables.QT_QPA_PLATFORM = "wayland";
  qt = {
    enable = true;
    platformTheme.name = "qt5ct";
    style = {
      # package = pkgs.adwaita-qt6;
      name = "kvantum";
    };
  };
  services.flatpak.overrides.global = {
    Context.filesystems = [
      "xdg-config/gtk-4.0:ro"
      "xdg-config/gtk-3.0:ro"
      "${pkgs.gruvbox-gtk-theme}/share/themes/:ro"
      "xdg-config/Kvantum:ro"
      "xdg-config/themes/:ro"
      "/run/current-system/sw/share/X11/fonts:ro"
      "/nix/store:ro"
      "xdg-data/fonts/:ro"
    ];
    Environment = {
      XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
    };
  };
  home.pointerCursor = {
    package = pkgs.graphite-cursors;
    gtk.enable = true;
    name = "graphite-dark";
  };
}
