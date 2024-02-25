{pkgs, upkgs, config, ...}:
{
  gtk.enable = true;
  gtk.theme.package = pkgs.gruvbox-gtk-theme;
  gtk.theme.name = "Gruvbox-Dark-BL";
}
