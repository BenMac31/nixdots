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

      # XiaServer only accepts the voxi key, and only for graphide-build (the
      # user the remote builders in hosts/nixBlade/remote-builds.nix log in
      # as). IdentitiesOnly above means an agent key is never offered unless
      # a block names it, so without this `ssh xiaserver` fails on publickey.
      matchBlocks.xiaserver = {
        host = "xiaserver xiaserver.tail028f45.ts.net 100.96.50.71 10.0.0.35 10.0.0.100";
        user = "graphide-build";
        identityFile = "~/.ssh/id_ed25519_voxi";
      };
    };

    # Enable SSH agent service to cache passphrases during session
    services.ssh-agent.enable = true;
  };
}

