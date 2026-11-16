{ lib, config, pkgs, ... }:
{
  options = {
    ai.reason = {
      enable = lib.mkEnableOption "the Reason Machines CLI";
    };
  };
  config = lib.mkIf config.ai.reason.enable {
    home.packages = [ (pkgs.unfree.callPackage ../../../../pkgs/reason-cli.nix { }) ];
  };
}
