{ pkgs, config, lib, ... }:
{
  home.packages = with pkgs; [
    pkgs.r2modman
    (pkgs.writeShellScriptBin "steam" ''
      ${pkgs.flatpak}/bin/flatpak run com.valvesoftware.Steam -silent "$@"
    '')
  ];
  services.flatpak = {
    packages = [
      #
      "com.valvesoftware.Steam"
      "net.lutris.Lutris"
      "org.prismlauncher.PrismLauncher"
      "net.veloren.airshipper"
    ];
    overrides = {
      "org.prismlauncher.PrismLauncher" = {
        Context = {
          filesystems = [
            "xdg-data/applications:create"
          ];
        };
      };
      "com.valvesoftware.Steam" = {
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
      "net.lutris.Lutris" = {
        Context = {
          filesystems = [
            "xdg-data/icons:create"
          ];
        };
      };
    };
  };
}
