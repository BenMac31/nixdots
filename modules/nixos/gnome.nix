{config, pkgs, inputs, ... }:

{
  services.xserver.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  # services.xserver.displayManager.autoLogin.enable = true;
  # services.xserver.displayManager.autoLogin.user = "greencheetah";
}
