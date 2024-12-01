{ pkgs, config, lib, ... }:
{
  systemd.user.settings.Manager.DefaultEnvironment = {
    PATH = "/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
  };
  xdg = {
    enable = true;
    portal = {
      enable = true;
      xdgOpenUsePortal = true;
      configPackages = with pkgs; [
        gnome-session
      ];
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };
    mime.enable = true;
    mimeApps.enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
    };
  };
}
