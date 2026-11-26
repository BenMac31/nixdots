{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./programming
    ./tui
    ./ai
    ./git.nix
    ./fastfetch.nix
    ./zsh.nix
    ./media.nix
    ./ssh.nix
    ./disk-watch.nix
    ./agent-scratch.nix
    ./build-cache-prune.nix
    ./gp-cache-prune.nix
    ./ubuntu-vm.nix
  ];
  config = {
    services.diskWatch.enable = lib.mkDefault (osConfig.services.diskGuard.enable or false);
    services.agentScratch = {
      enable = lib.mkDefault (osConfig.services.diskGuard.enable or false);
      migration.enable = lib.mkDefault true;
      paths = lib.mkDefault [
        "Projects/wt" "Projects/graphide/scratch" "Projects/IvorySummit"
        ".cache/gp" ".cache/go-build" ".cache/gred-rs" ".cache/tmp-overflow"
        ".local/share/containers"
      ];
    };
    services.buildCachePrune.enable = lib.mkDefault (osConfig.services.diskGuard.enable or false);
    services.gpCachePrune.enable = lib.mkDefault (osConfig.services.diskGuard.enable or false);
    tui.enable = lib.mkDefault true;
    home.packages = with pkgs; [
      (lib.mkIf config.desktop.enable brightnessctl)
      (lib.mkIf config.desktop.enable wl-clipboard)
      libnotify
      jq
      yt-dlp
    ];
    programs = {
      fastfetch.enable = lib.mkDefault true;
      gpg.enable = true;
      ssh.enable = lib.mkDefault true;
      direnv = {
        enable = true;
        nix-direnv.enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
        enableFishIntegration = true;
      };
    };
  };
}
