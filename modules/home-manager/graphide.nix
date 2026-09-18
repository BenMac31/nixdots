{ config, lib, osConfig, ... }:
{
  imports = [
    ./term/graphide.nix
    ./term/yc.nix
    ./term/ai/accounts.nix
  ] ++ lib.optionals osConfig.programs.hyprland.enable [
    ./desktop/env/wm/graphide-shell.nix
  ];
  config = lib.mkIf osConfig.programs.hyprland.enable {
    programs.graphide-shell.enable = lib.mkDefault true;
  };
}
