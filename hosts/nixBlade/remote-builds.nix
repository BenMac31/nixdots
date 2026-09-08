# Offload nix builds from this laptop to the Graphide build host.
#
# Four threads here, twelve there. Anything nix builds -- a fork release, a Go
# closure, a NixOS system -- is work this box does badly and XiaServer does
# well, so the laptop evaluates and the server builds.
#
# The thing that makes this fiddly: builds do not run as the logged-in user.
# nix-daemon runs as root, so it is ROOT that opens the ssh connection to the
# builder, and root has neither the user's ssh config nor the user's
# known_hosts. Two consequences, both handled below:
#
#   1. sshKey points at the user's existing private key. The host already
#      trusts that key, so nothing has to be generated or deployed. (Owner
#      decision; the alternative was a dedicated root key, which costs a sudo
#      step on the laptop and a redeploy on the host.)
#   2. programs.ssh.knownHosts pins the host's ed25519 key system-wide, so
#      root's ssh never stops at a host-key prompt it has no tty to answer.
#      Verified against `ssh-keyscan 10.0.0.35` on 2026-09-07.
#
# builders-use-substitutes lets the host fetch from cache.nixos.org itself
# rather than having every dependency pushed to it over the LAN.
#
# This is a preference, not a requirement: if the host is off or unreachable,
# nix logs the failed connection and builds locally instead. Nothing here can
# wedge a build.
{ ... }:
{
  nix.distributedBuilds = true;
  nix.settings.builders-use-substitutes = true;

  nix.buildMachines = [
    {
      hostName = "10.0.0.35";
      sshUser = "graphide-build";
      sshKey = "/home/greencheetah/.ssh/id_ed25519_voxi";
      system = "x86_64-linux";
      protocol = "ssh-ng";
      maxJobs = 3;
      speedFactor = 4;
      supportedFeatures = [ "big-parallel" "kvm" "nixos-test" "benchmark" ];
    }
  ];

  programs.ssh.knownHosts."10.0.0.35".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWFmoYiRIbUToYku4tbARtl7W0OLx+lSt2cwV0iSaj1";
}
