{ config, lib, pkgs, ... }:

{
  programs.ssh = {
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

  # Enable SSH agent service to cache passphrases during session
  services.ssh-agent.enable = true;

  # Ensure SSH_AUTH_SOCK is set in zsh
  programs.zsh.initExtra = lib.mkBefore ''
    export SSH_AUTH_SOCK="/run/user/$(id -u)/ssh-agent"
  '';
}