{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./programming
    ./tui
    ./ai.nix
    ./zsh.nix
    ./media.nix
  ];
  config = {
    tui.enable = lib.mkDefault true;
    home.packages = with pkgs; [
      (lib.mkIf config.desktop.enable brightnessctl)
      (lib.mkIf config.desktop.enable wl-clipboard)
      fastfetch
      libnotify
      jq
      yt-dlp
    ];
    programs = {
      gpg.enable = true;
      ssh = {
        enable = true;
        # Enable connection sharing to reuse authenticated connections
        # This allows SSH to cache authentication during a session
        extraConfig = ''
          # Add keys to agent automatically
          AddKeysToAgent yes
          
          # Use SSH agent for authentication
          IdentitiesOnly yes
        '';
      };
    };

    # Enable SSH agent service to cache passphrases during session
    services.ssh-agent.enable = true;
  };
}
