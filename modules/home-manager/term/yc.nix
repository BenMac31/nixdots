{ lib, config, pkgs, ... }:
{
  options = {
    yc = {
      enable = lib.mkEnableOption "Enable the YC CLI (Bookface + YC Agent)";
    };
  };
  config = lib.mkIf config.yc.enable {
    home.packages = [ pkgs.yc-cli ];

    # ~/.yc/bin is where upstream's installer drops its own copy of the binary,
    # which the packaged one replaces; prune it so it doesn't shadow ours.
    home.activation.pruneYcInstallerBin =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run rm -rf "$HOME/.yc/bin"
      '';
  };
}
