# Offload nix builds from this laptop to the Graphide build host.
#
# Four threads here, twelve there. Anything nix builds -- a fork release, a Go
# closure, a NixOS system -- is work this box does badly and XiaServer does
# well, so the laptop evaluates and the server builds.
#
# The builder is listed TWICE, once by LAN address and once by tailnet
# address. Both entries are the same machine. This decision has now been made
# three times in alternating directions, so the whole history is kept here;
# a fourth change to it should know all of it.
#
# The file first listed only the Tailscale IP, on the reasoning that
# 100.96.50.71 follows the machine -- direct path at home, over the tailnet
# anywhere else -- so one address covers both. That assumed the tailnet is
# always up. On 2026-09-08 it was not: `tailscale down` had been run on this
# laptop, the builder was sitting on the same LAN two metres away with twelve
# idle cores, and every build ran locally because the only address nix knew
# was unroutable. Nix did exactly what it promises below -- logged the failed
# connection and built locally -- which is to say the laptop got slower and
# nothing said why. A LAN entry was added alongside to cover that.
#
# On 2026-09-09 the tailnet entry was removed, by owner decision. Tailscale
# was still stopped on this laptop, so the entry only ever cost a 10-second
# ConnectTimeout before nix moved on. What went with it was off-LAN offload:
# away from this house there was no build host at all, and the symptom was the
# 2026-09-08 one mirrored -- four threads, and nothing in the output saying
# why. The removal recorded its own fix: re-add the entry, and `tailscale up`
# as the other half, because the entry is inert without it.
#
# Later on 2026-09-09 the entry was re-added, by owner decision, which is the
# state below. The premise of the removal no longer held: tailscaled is
# running again, XiaServer is up on the tailnet, and `tailscale status` shows
# that path as DIRECT rather than DERP-relayed, so the tailnet entry is a
# real build path and not a timeout to wait out. `ssh graphide-build@` over
# both addresses was confirmed working before this was written. The cost is
# back to what it was on 2026-09-08: if Tailscale is stopped again, this entry
# reverts to a 10-second stall per build with nothing explaining it. That is
# the thing to check first if builds start feeling slow for no reason.
#
# There is no hostname to use in place of either literal IP. All three
# candidates were checked on 2026-09-08 and none of them resolve here:
#
#   - `xiaserver.tail028f45.ts.net` is served by Tailscale's own resolver, so
#     it dies in exactly the case the LAN entry exists to cover.
#   - `xiaserver.local` needs mDNS at both ends. This host's nsswitch has no
#     mdns4_minimal (the avahi block in modules/nixos/default.nix is commented
#     out), and more decisively the builder does not run avahi at all.
#   - bare `xiaserver` has nothing to resolve against -- resolv.conf is two
#     Comcast servers with no local search domain. XiaServer is also SHARED
#     INTO this tailnet from tail028f45.ts.net rather than being one of our
#     own nodes, and shared nodes answer only to their full MagicDNS name.
#
# XiaServer is not in this flake's hosts/, so the mDNS end of that is not a
# config we can fix from here. Literal IPs keep DNS out of root's ssh path
# entirely, which is the property actually worth having.
#
# maxJobs is 2 on each entry, down from the 3 the single-entry layout ran.
# Nix treats the two entries as distinct machines with separate slot pools,
# so the ceiling is their sum, not the larger of them, and at home both paths
# are live at once. 2 each is the split the 2026-09-08 two-entry layout used
# and is restored here rather than re-derived. Note that 2+2 still exceeds
# the 3 the single-entry layout called XiaServer's exact fit at cores=4; the
# ceiling only binds when four jobs are actually queued, and it was accepted
# on that basis.
#
# speedFactor is 4 on the LAN entry and 3 on the tailnet one. Nix prefers the
# higher number, so at home -- where both entries answer -- work lands on the
# LAN path first and only spills onto the tailnet address for the same
# machine. Away from home only one entry answers and the ordering is moot.
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
#      All three names below are the same machine carrying the same key. The
#      MagicDNS name stays pinned even though it is not a build machine, so
#      that scripts/remote.sh does not need a fresh keyscan:
#      `ssh-keyscan 100.96.50.71` on 2026-09-08 returned exactly the key that
#      `ssh-keyscan 10.0.0.35` returned on 2026-09-07.
#
# ConnectTimeout bounds the cost of an address that does not answer. A builder
# powered off, or 10.0.0.35 being asked for from a coffee shop, leaves ssh
# waiting out a full TCP timeout -- a couple of minutes -- and the build stalls
# that long before nix gives up and goes local. Ten seconds is far more than
# the working path ever needs. It is set for both addresses, which is also
# what `scripts/remote.sh` in the monorepo inherits when it probes the LAN and
# then the tailnet to pick a destination.
#
# The knownHosts pin below is what makes the LAN entry safe to carry off the
# home network. 10.0.0.0/8 is everybody's private range, so on a hotel or cafe
# LAN 10.0.0.35 may well resolve to a stranger's machine that happens to
# answer on 22. It will not match the pinned ed25519 key, root's ssh refuses
# the connection, and nix skips that machine -- which is the correct outcome
# and happens without a prompt nobody is there to answer.
#
# builders-use-substitutes lets the host fetch from cache.nixos.org itself
# instead of having every dependency pushed to it from here, which mattered on
# the LAN and matters considerably more over hotel wifi.
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
      hostName = "10.0.0.100";
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

  programs.ssh.knownHosts.xiaserver = {
    hostNames = [
      "100.96.50.71"
      "xiaserver.tail028f45.ts.net"
      "10.0.0.100"
    ];
    publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWFmoYiRIbUToYku4tbARtl7W0OLx+lSt2cwV0iSaj1";
  };

  programs.ssh.extraConfig = ''
    Host 100.96.50.71 10.0.0.100
      ConnectTimeout 10
  '';
}
