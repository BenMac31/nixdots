# Keep the desktop usable while several coding agents build and test at once.
# The Go-side caps (build-slot queue, GOFLAGS, GOMAXPROCS) live in the monorepo.
{ pkgs, ... }:
{
  # The claude and codex wrappers in term/ai/accounts.nix start each session
  # here. Limits are for the slice as a whole, so all sessions share one budget:
  # MemoryHigh throttles and reclaims, MemoryMax is the kill line.
  systemd.user.slices.agents = {
    description = "Coding agents and everything they spawn";
    sliceConfig = {
      CPUWeight = 30;
      # The weight only yields to the desktop; agents competing with each
      # other still fill all eight threads. The quota keeps two free.
      CPUQuota = "600%";
      IOWeight = 30;
      MemoryHigh = "8G";
      MemoryMax = "11G";
    };
  };

  # The dev editor agents launch moves itself into its own
  # app-code\x2doss\x2ddev-<pid>.scope, out of agents.slice and any cap it was
  # started under. This prefix drop-in caps every such scope. It is a package
  # because the NixOS unit generator mangles backslashes in unit names.
  systemd.packages = [
    (pkgs.writeTextDir "lib/systemd/user/app-code\\x2doss\\x2ddev-.scope.d/cpu.conf" ''
      [Scope]
      CPUQuota=100%
      CPUWeight=30
    '')
  ];

  # The defaults (cores = 0, max-jobs = auto) allow 64 build threads on this
  # 8-thread laptop.
  nix.settings = {
    cores = 4;
    max-jobs = 2;
  };
  # Builds run under nix-daemon, out of reach of agents.slice.
  systemd.services.nix-daemon.serviceConfig = {
    CPUWeight = 30;
    IOWeight = 30;
  };

  # Fills before the swapfile, which stays because hibernation needs it.
  zramSwap.enable = true;
}
