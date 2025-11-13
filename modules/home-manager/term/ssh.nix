{ config, lib, pkgs, osConfig, ... }:

{
  config = lib.mkIf config.programs.ssh.enable {
    programs.ssh = {
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

    # Ensure SSH_AUTH_SOCK is set globally
  };
}

