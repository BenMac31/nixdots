{ config, lib, osConfig, ... }:
{
  imports = [
    ./term/graphide.nix
    ./term/transcripts.nix
    ./term/yc.nix
    ./term/ai/accounts.nix
    ./term/ai/pool.nix
    ./desktop/apps/graphide-browser.nix
  ] ++ lib.optionals osConfig.programs.hyprland.enable [
    ./desktop/env/wm/graphide-shell.nix
  ];
  config = lib.mkIf osConfig.programs.hyprland.enable {
    programs.graphide-shell.enable = lib.mkDefault true;
  };
}
