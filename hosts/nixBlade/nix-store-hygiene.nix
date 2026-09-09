{ ... }:
# Store hygiene for a machine that builds the Graphide monorepo all day.
#
# The workload is unusual and both settings below are sized for it. Ten agent
# sessions share a handful of always-dirty checkouts, and nix caches a flake by
# revision only when the tree is clean. A dirty tree gets re-snapshotted on
# every distinct content hash, so an ordinary edit-build cycle mints a fresh
# ~150 MB copy of the whole tracked tree.
#
# Measured 2026-09-09: 91 of those snapshots were resident, 13.1 GB in total,
# and two consecutive ones differed by 37 files out of 6026 -- 0.6%. The store
# was 123 GB on a 953 GB disk at 83% full.
{
  # ── Deduplicate ──────────────────────────────────────────────────────────
  # Those 91 snapshots share 99.4% of their content and were not sharing a
  # single inode: `stat -c %h` on a file inside one read 1. /nix/store/.links
  # was populated, so `nix-store --optimise` had been run by hand once and
  # never made to repeat.
  #
  # The timer, not `nix.settings.auto-optimise-store`. Inline optimisation
  # hashes every file as it is added to the store, and this host is already
  # throttled to cores = 4 / max-jobs = 2 in agent-throttle.nix precisely
  # because build CPU competes with the agents' own turns. Reclaiming the same
  # bytes a few hours later costs nothing that anyone is waiting on. Flip to
  # inline only if peak disk between runs becomes the problem rather than
  # steady-state disk.
  nix.optimise = {
    automatic = true;
    dates = [ "03:30" ];
  };

  # ── Reclaim on disk pressure, not only on the calendar ───────────────────
  # modules/nixos/default.nix already sets nix.gc weekly with
  # --delete-older-than 7d, and that is worth keeping: it bounds generations.
  # What it does not do is react. On 2026-09-09 the timer was enabled and had
  # never fired -- next trigger four days out -- while the store took on about
  # 5 GB an hour of near-identical snapshots. A weekly sweep cannot hold a line
  # against that.
  #
  # min-free/max-free are the nix-daemon's own answer: when free space falls
  # below min-free it collects until max-free is free, in the middle of a
  # build if that is when it happens. Unrooted flake source snapshots are
  # exactly what it takes first, which is the garbage this workload makes.
  #
  # Sized for the 953 GB disk this store sits on: start at 40 GiB free, which
  # is several hours of headroom at the observed rate, and stop at 120 GiB so
  # it is not re-triggering constantly.
  nix.settings = {
    min-free = 40 * 1024 * 1024 * 1024;
    max-free = 120 * 1024 * 1024 * 1024;
  };
}
