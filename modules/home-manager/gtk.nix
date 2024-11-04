{pkgs, inputs, config, ...}:
{
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
}
