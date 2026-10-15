# Offload nix builds to XiaServer, which has twelve threads to this laptop's
# four. Off for now; the machine list and host-key pin stay because the
# monorepo's utilities/scripts/remote.sh relies on the pin.
{ ... }:
{
  nix.distributedBuilds = false;
  nix.settings.builders-use-substitutes = true;

  # The same machine twice: by LAN address for home with Tailscale down, and by
  # tailnet address for away. Nix prefers the higher speedFactor and counts each
  # entry's maxJobs separately. No name for it resolves without Tailscale.
  # nix-daemon connects as root, so sshKey is the user's key the host trusts.
  nix.buildMachines = [
    {
      hostName = "10.0.0.35"; # keep in step with remote.sh
      sshUser = "graphide-build";
      sshKey = "/home/greencheetah/.ssh/id_ed25519_voxi";
      system = "x86_64-linux";
      protocol = "ssh-ng";
      maxJobs = 2;
      speedFactor = 4;
      supportedFeatures = [ "big-parallel" "kvm" "nixos-test" "benchmark" ];
    }
    {
      hostName = "100.96.50.71";
      sshUser = "graphide-build";
      sshKey = "/home/greencheetah/.ssh/id_ed25519_voxi";
      system = "x86_64-linux";
      protocol = "ssh-ng";
      maxJobs = 2;
      speedFactor = 3;
      supportedFeatures = [ "big-parallel" "kvm" "nixos-test" "benchmark" ];
    }
  ];

  # Root has no known_hosts and no tty to answer a prompt. The pin also stops a
  # stranger's 10.0.0.35 on someone else's LAN from being used.
  programs.ssh.knownHosts.xiaserver = {
    hostNames = [
      "100.96.50.71"
      "xiaserver.tail028f45.ts.net"
      "10.0.0.35"
    ];
    publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWFmoYiRIbUToYku4tbARtl7W0OLx+lSt2cwV0iSaj1";
  };

  # An address that does not answer would otherwise stall each build for minutes.
  programs.ssh.extraConfig = ''
    Host 100.96.50.71 10.0.0.35
      ConnectTimeout 10
  '';
}
