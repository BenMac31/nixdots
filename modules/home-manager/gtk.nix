{pkgs, config, ...}:
{
  gtk = {
    enable = true;
    theme = {
      package = pkgs.gruvbox-gtk-theme;
      name = "Gruvbox-Dark-BL";
    };
    iconTheme = {
      package = pkgs.morewaita-icon-theme;
      name = "MoreWaita";
    };
  };
  home.file.gruvbox-gtk = {
    source = config.lib.file.mkOutOfStoreSymlink "${pkgs.gruvbox-gtk-theme}/share/themes/Gruvbox-Dark-BL";
    target = "${config.xdg.dataHome}/themes/Gruvbox-Dark-BL";
  };
  qt = {
    enable = true;
    style.name = "adwaita-dark";
    platformTheme = "adwaita";
  };
}
