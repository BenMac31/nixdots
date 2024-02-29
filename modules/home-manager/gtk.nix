{pkgs, config, ...}:
{
  gtk = {
    enable = true;
    theme = {
      package = pkgs.gruvbox-gtk-theme;
      name = "Gruvbox-Dark-BL";
    };
    iconTheme = {
      package = pkgs.unstable.morewaita-icon-theme;
      name = "MoreWaita";
    };
  };
}
