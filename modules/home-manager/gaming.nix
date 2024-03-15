{pkgs, config, lib, ...}:
{
home.packages = with pkgs; [
     pkgs.r2modman
    (pkgs.writeShellScriptBin "steam" ''
      ${pkgs.flatpak}/bin/flatpak run com.valvesoftware.Steam "$@"
     '')
     ];
  services.flatpak = {
    packages = [ #
      "com.valvesoftware.Steam"
      "com.valvesoftware.Steam.Utility.gamescope"
      "net.lutris.Lutris"
      "org.prismlauncher.PrismLauncher"
    ];
    overrides = {
      "com.valvesoftware.Steam"= {
        Context = {
          filesystems = [
            "xdg-config/r2modmanPlus-local:rw"
            "xdg-data/icons:create"
            "xdg-data/applications:create"
          ];
          device = [
            "dri"
          ];
        };
      };
      "net.lutris.Lutris"= {
        Context = {
          filesystems = [
            "xdg-data/icons:create"
          ];
        };
      };
    };
  };
}
