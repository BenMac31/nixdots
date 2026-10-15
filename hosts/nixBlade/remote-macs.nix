# macOS test machines opened from Graphide's desktop picker. The pin lets the
# non-interactive reachability probe connect without a host-key prompt.
{ ... }:
{
  programs.ssh.knownHosts.bans-mac-mini = {
    hostNames = [
      "10.0.0.217"
      "Bans-Mac-Mini.local"
      "graphide-m6"
    ];
    publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFR6tDhrJsvG0FGsqbxmv94LkJIMWwvaDKX0sRTCnorK";
  };

  # A name for scripts and one-off sessions. The compute dispatcher probes the
  # IP and Bonjour name instead, so an offline Mac falls back to XiaServer.
  programs.ssh.extraConfig = ''
    Host graphide-m6
      HostName 10.0.0.217
      User ban
      ConnectTimeout 5
  '';
}
