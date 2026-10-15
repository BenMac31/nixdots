{ lib, config, pkgs, inputs, flakeAttr, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  # The shell's `gr` runs the same build as the running daemon. grug points
  # ~/.config/graphide/bin/gr at its own gr on every start (monolith
  # grug/harness, EnsureGrShim), so this follows a `gdev swap` to a newer
  # daemon. Without it the shell keeps the release module's gr, which the
  # frozen `ff` channel holds at 0.1.27, and a command only the newer build
  # has (`gr cloud`) is missing. The release gr still runs when no daemon has
  # made the link yet, or when the link would lead back here.
  releaseGr =
    let gp = config.graphide.releaseFlake.packages.${system};
    in if config.graphide.variant == "prod" then gp.gr-prod else gp.gr-dev;
  grFollowsDaemon = pkgs.writeShellScriptBin "gr" ''
    shim="''${XDG_CONFIG_HOME:-$HOME/.config}/graphide/bin/gr"
    if [ -x "$shim" ]; then
      self=$(${pkgs.coreutils}/bin/readlink -f "$0")
      target=$(${pkgs.coreutils}/bin/readlink -f "$shim")
      if [ -n "$target" ] && [ "$target" != "$self" ]; then
        exec "$shim" "$@"
      fi
    fi
    exec ${releaseGr}/bin/gr "$@"
  '';
in {
  imports = [ inputs.graphide-tools.homeManagerModules.graphide ];
  # gdev: per-worktree isolated instances. From graphide-tools, not the
  # release-pinned `graphide`, so the updater never rolls it back.
  home.packages = lib.mkIf config.graphide.enable [
    inputs.graphide-tools.packages.${system}.gdev
    (lib.hiPrio grFollowsDaemon)
  ];
  graphide.releaseFlake = inputs.graphide;
  graphide.autoUpdate = {
    flakeAttr = flakeAttr;
    homeManagerPackage = inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager;
  };
  graphide.checkoutSync = {
    enable = lib.mkDefault config.graphide.enable;
    checkout = "${config.home.homeDirectory}/Projects/graphide/graphide";
    sshAuthSock = "%t/ssh-agent";
    # The only local state sync may discard: the generated graph tree plus
    # every agent-config target (listed in each repo's .agent-config-manifest).
    # An `agent-config sync` run in the shared checkout rewrites those in place
    # and used to stall the fast-forward for days (2026-09-15: 146 behind).
    # Directory roots rather than exact files, so a new skill or hook does not
    # re-break it; the cost is that an untracked, non-ignored file a peer drops
    # under one of these dirs is cleaned on the next cycle. Drop an entry once
    # git stops tracking it (gred/, 2026-10-13): before monolith c3a856832 one
    # dead entry made `git restore` clear nothing.
    allowlist = [
      ".graphide/authored"
      ".agents" ".claude" ".codex" ".cursor"
      "AGENTS.md" "CLAUDE.md" "QUIRKS.md" ".agent-config-manifest" "orca.yaml"
      "website/.claude" "website/.codex" "website/.cursor" "website/.agent-config-manifest"
    ];
  };
}
