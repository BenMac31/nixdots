{ pkgs, inputs, lib, config, ... }:
{
  imports = with inputs; [
    nix-colors.homeManagerModules.default
  ];
  colorScheme = lib.mkDefault inputs.nix-colors.colorSchemes.gruvbox-dark-medium;
  gtk = {
    enable = lib.mkIf config.desktop.enable true;
    gtk4.theme = lib.mkIf config.desktop.enable config.gtk.theme;
    theme = {
      package = pkgs.gruvbox-gtk-theme;
      name = "Gruvbox-Dark";
    };
    iconTheme = {
      package = pkgs.gruvbox-dark-icons-gtk;
      name = "Oomox-gruvbox-dark";
    };
  };
  xdg.configFile = lib.mkIf config.desktop.enable {
    "Kvantum/gruvbox-kvantum/".source = "${inputs.gruvbox-kvantum}/gruvbox-kvantum/";
    "Kvantum/kvantum.kvconfig".text = "[General]\ntheme=gruvbox-kvantum";
  };
  home.sessionVariables = lib.mkIf config.desktop.enable {
    QT_QPA_PLATFORM = "wayland";
  };
  qt = {
    enable = lib.mkIf config.desktop.enable true;
    platformTheme.name = "qt5ct";
    style = {
      # package = pkgs.adwaita-qt6;
      name = "kvantum";
    };
  };
  services.flatpak = lib.mkIf config.desktop.enable {
    # Kvantum is a Flatpak extension, not a regular app — it must match the KDE
    # platform version used by Qt flatpaks (e.g. qBittorrent on org.kde.Platform//6.10).
    packages = [
      "org.kde.KStyle.Kvantum//6.10"
    ];
    overrides.global = {
      Context.filesystems = [
        "xdg-config/gtk-4.0:ro"
        "xdg-config/gtk-3.0:ro"
        "${pkgs.gruvbox-gtk-theme}/share/themes/:ro"
        "xdg-config/Kvantum:ro"
        "xdg-config/qt5ct:ro"
        "xdg-config/themes/:ro"
        "/run/current-system/sw/share/X11/fonts:ro"
        "/nix/store:ro"
        "xdg-data/fonts/:ro"
      ];
      Environment = {
        XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
        QT_STYLE_OVERRIDE = "kvantum";
        QT_QPA_PLATFORMTHEME = "qt5ct";
      };
    };
  };
  home.pointerCursor = {
    package = pkgs.graphite-cursors;
    gtk.enable = true;
    name = "graphite-dark";
  };
}
