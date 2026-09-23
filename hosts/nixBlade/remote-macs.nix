# Host identities for the physical macOS test machines opened from Graphide's
# Quickshell desktop picker. Pinning the key makes the non-interactive reachability
# probe safe and keeps a first connection from disappearing behind a prompt.
{ ... }:
{
  programs.ssh.knownHosts.bans-mac-mini = {
    hostNames = [
      "10.0.0.217"
      "Bans-Mac-Mini.local"
    ];
    publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFR6tDhrJsvG0FGsqbxmv94LkJIMWwvaDKX0sRTCnorK";
  };
}
