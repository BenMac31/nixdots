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
    # A restarted agent comes back empty, and the GitHub and build-worker key
    # (id_rsa) has a passphrase only Ben can type. So a home-manager activation
    # (the daily nixos-upgrade timer, or any switch) keeps the running agent
    # even when its unit changed; it picks up a new openssh at the next login.
    # This happened on 11-01, 11-02 and 11-03 and stopped every agent's ssh.
    systemd.user.services.ssh-agent.Unit.X-RestartIfChanged = false;
  };
}

