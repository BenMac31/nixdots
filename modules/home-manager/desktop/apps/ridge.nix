{ config, lib, pkgs, ... }:

{
  options.ridge.enable = lib.mkEnableOption "Ridge fingerprint terminal";

  config = lib.mkIf (config.desktop.enable && config.ridge.enable) {
    home.packages = [ pkgs.ridge ];
  };
}
