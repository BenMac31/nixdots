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
  qt = {
    enable = true;
    style.name = "adwaita-dark";
    platformTheme = "gnome";
  };
}
