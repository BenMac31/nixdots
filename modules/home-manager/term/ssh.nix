{ config, lib, pkgs, osConfig, ... }:

{
  config = lib.mkIf config.programs.ssh.enable {
    programs.ssh = {
      extraConfig = ''
        AddKeysToAgent yes
        IdentitiesOnly yes
      '';

      # XiaServer accepts only the voxi key, for graphide-build. IdentitiesOnly
      # offers an agent key only where a block names it.
      matchBlocks.xiaserver = {
        host = "xiaserver xiaserver.tail028f45.ts.net 100.96.50.71 10.0.0.35 10.0.0.100";
        user = "graphide-build";
        identityFile = "~/.ssh/id_ed25519_voxi";
      };
    };

    services.ssh-agent.enable = true;
  };
}

