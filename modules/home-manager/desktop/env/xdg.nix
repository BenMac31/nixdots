{ pkgs, config, lib, osConfig, ... }:

let
  gnomeEnabled =
    lib.attrByPath [ "services" "desktopManager" "gnome" "enable" ] false osConfig;
in
{
  config = lib.mkIf config.desktop.enable {
    systemd.user.settings.Manager.DefaultEnvironment = {
      PATH = "/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
    };
    xdg = {
      enable = true;
      portal = {
        enable = true;
        xdgOpenUsePortal = true;
        configPackages = with pkgs; [
          (lib.mkIf gnomeEnabled gnome-session)
        ];
        extraPortals = with pkgs; [
          (lib.mkIf gnomeEnabled xdg-desktop-portal-gtk)
          (lib.mkIf osConfig.programs.hyprland.enable xdg-desktop-portal-hyprland)
        ];
      };
      configFile."hypr/xdph.conf" = lib.mkIf osConfig.programs.hyprland.enable {
        text = ''
          screencopy {
            allow_token_by_default = true
          }
        '';
      };
      mime.enable = true;
      mimeApps.enable = true;
      userDirs = {
        enable = true;
        createDirectories = true;
      };
    };
  };
}
