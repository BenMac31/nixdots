{pkgs, upkgs, config, ...}:
{
  gtk.enable = true;
  gtk.theme.package = upkgs.gruvbox-gtk-theme;
  gtk.theme.name = "gruvbox-gtk-theme-BL";
}
