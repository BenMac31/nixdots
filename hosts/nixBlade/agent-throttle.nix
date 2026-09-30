# Keep the laptop usable while several coding agents build and test at once.
#
# Measured 2026-09-07 with seven Claude Code sessions up: 7 GB of the 16 GB
# swapfile in use and a memory-stall PSI of 28%, i.e. every task on the box
# blocked on memory for over a quarter of the time. Four cores and 15 GB do not
# get faster by scheduling, but they can stop taking the desktop down with them.
#
# Three levers, all undone by dropping this file from the host's imports:
#   1. an `agents.slice` user slice with a low CPU/IO weight and a memory
#      ceiling, which the claude/codex wrappers start each session inside;
#   2. nix builds capped at two jobs of four cores instead of eight of eight,
#      and nix-daemon, where builds actually run (outside the user's cgroup,
#      so the slice cannot reach them), given the same low weight;
#   3. zram swap ahead of the swapfile, so the swapping that still happens is
#      compressed in RAM instead of paged to disk. The swapfile stays: lid
#      close hibernates, and hibernation needs a real swap device.
#
# The Go-side caps (the build-slot queue, GOFLAGS, GOMAXPROCS) live in the
# monorepo's scripts/ and flake.nix, not here.
{ pkgs, ... }:
{
  # MemoryHigh throttles and reclaims; MemoryMax is the kill line. Both are
  # for the slice as a whole, so seven sessions share one budget rather than
  # each getting their own. Agents get squeezed first and the desktop last,
  # and a runaway race-detector run dies before it takes the box with it.
  systemd.user.slices.agents = {
    description = "Coding agents and everything they spawn";
    sliceConfig = {
      CPUWeight = 30;
      # A weight only yields to the desktop; agents contending with each other
      # still filled all eight threads (load 60 on 2026-09-29). The quota keeps
      # two threads free regardless.
      CPUQuota = "600%";
      IOWeight = 30;
      MemoryHigh = "8G";
      MemoryMax = "11G";
    };
  };

  # The dev editor that agents launch moves its main process into its own
  # app-code\x2doss\x2ddev-<pid>.scope under app.slice, out of agents.slice and
  # out of any systemd-run cap it was started under; one ran at 115% CPU. This
  # prefix drop-in applies to every such scope. It ships as a package because
  # NixOS's unit generator mangles the backslashes in a systemd.user.units name.
  systemd.packages = [
    (pkgs.writeTextDir "lib/systemd/user/app-code\\x2doss\\x2ddev-.scope.d/cpu.conf" ''
      [Scope]
      CPUQuota=100%
      CPUWeight=30
    '')
  ];

  # The `claude` and `codex` wrappers in modules/home-manager/term/ai/
  # accounts.nix put each session in this slice. That used to be a shell alias
  # here, which any later `claude` alias silently replaced.

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
