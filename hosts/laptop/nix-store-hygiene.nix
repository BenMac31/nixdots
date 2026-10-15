{ ... }:
# Agent sessions share always-dirty checkouts of the Graphide monorepo, and nix
# snapshots a dirty flake on every distinct content hash: ~150 MB of nearly
# identical source per edit-build cycle, around 5 GB an hour.
{
  # Hard-links the duplicate files in those snapshots. A timer rather than
  # auto-optimise-store, which hashes inline and competes with the agents for
  # CPU; agent-throttle.nix caps builds for the same reason.
  nix.optimise = {
    automatic = true;
    dates = [ "03:30" ];
  };

  # The weekly nix.gc in modules/nixos cannot keep up with that rate. Below
  # min-free the daemon collects until max-free is free, mid-build if need be,
  # and unrooted source snapshots are what it takes first.
  nix.settings = {
    min-free = 40 * 1024 * 1024 * 1024;
    max-free = 120 * 1024 * 1024 * 1024;
  };
}
