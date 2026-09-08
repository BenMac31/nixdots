# Keep the laptop usable while several coding agents build and test at once.
#
# Measured 2026-09-07 with seven Claude Code sessions up: 7 GB of the 16 GB
# swapfile in use and a memory-stall PSI of 28%, i.e. every task on the box
# blocked on memory for over a quarter of the time. Four cores and 15 GB do not
# get faster by scheduling, but they can stop taking the desktop down with them.
#
# Three levers, all undone by dropping this file from the host's imports:
#   1. an `agents.slice` user slice with a low CPU/IO weight and a memory
#      ceiling, and a `claude` alias that starts each session inside it;
#   2. nix builds capped at two jobs of four cores instead of eight of eight,
#      and nix-daemon, where builds actually run (outside the user's cgroup,
#      so the slice cannot reach them), given the same low weight;
#   3. zram swap ahead of the swapfile, so the swapping that still happens is
#      compressed in RAM instead of paged to disk. The swapfile stays: lid
#      close hibernates, and hibernation needs a real swap device.
#
# The Go-side caps (the build-slot queue, GOFLAGS, GOMAXPROCS) live in the
# monorepo's scripts/ and flake.nix, not here.
{ ... }:
{
  # MemoryHigh throttles and reclaims; MemoryMax is the kill line. Both are
  # for the slice as a whole, so seven sessions share one budget rather than
  # each getting their own. Agents get squeezed first and the desktop last,
  # and a runaway race-detector run dies before it takes the box with it.
  systemd.user.slices.agents = {
    description = "Coding agents and everything they spawn";
    sliceConfig = {
      CPUWeight = 30;
      IOWeight = 30;
      MemoryHigh = "8G";
      MemoryMax = "11G";
    };
  };

  # An interactive `claude` lands in the slice; a script calling the binary
  # is unaffected, and so are sessions Paseo, Orca or Cursor start themselves.
  # --scope keeps the session in this terminal with its environment intact.
  environment.shellAliases.claude =
    "systemd-run --user --scope --slice=agents.slice --quiet claude";

  # Defaults are cores = 0 (every thread per build) and max-jobs = auto (one
  # build per thread): up to 64 build threads on an 8-thread laptop before a
  # single test runs.
  nix.settings = {
    cores = 4;
    max-jobs = 2;
  };
  systemd.services.nix-daemon.serviceConfig = {
    CPUWeight = 30;
    IOWeight = 30;
  };

  # Half of RAM as compressed swap (the module default), at a higher priority
  # than the swapfile so it fills first.
  zramSwap.enable = true;
}
