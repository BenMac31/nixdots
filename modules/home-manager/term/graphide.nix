{ lib, config, pkgs, inputs, flakeAttr, ... }:
let
  router = config.services.ai-router;
  wrap = ''
    for exe in gred gr grug grat; do
      if [ -e "$out/bin/$exe" ]; then
        wrapProgram "$out/bin/$exe" \
          --set AI_ROUTER_URL ${lib.escapeShellArg router.url} \
          --set CODEX_PATH ${lib.escapeShellArg "${config.home.profileDirectory}/bin/codex"} \
          --prefix PATH : ${lib.escapeShellArg "${config.home.profileDirectory}/bin"}
      fi
    done
  '';
  route = package: package.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (old.postFixup or "") + wrap;
  });
  # The Go programs only need new launchers, not a recompilation. gred above
  # retains overrideAttrs because the release module replaces its tarball src.
  routeCommands = package: pkgs.symlinkJoin {
    name = "${package.name}-routed";
    inherit (package) pname meta;
    paths = [ package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = wrap;
  };
  system = pkgs.stdenv.hostPlatform.system;
  packages = inputs.graphide.packages.${system};
in {
  imports = [ inputs.graphide-tools.homeManagerModules.graphide ];
  # gdev: per-worktree isolated instances. From graphide-tools, not the
  # release-pinned `graphide`, so the updater never rolls it back.
  home.packages = lib.mkIf config.graphide.enable [
    inputs.graphide-tools.packages.${system}.gdev
  ];
  # The release's desktop launcher and bundled daemon inherit these settings.
  # Keeping the override here also reapplies it after automatic release updates.
  graphide.releaseFlake = if router.enable then inputs.graphide // {
    packages = inputs.graphide.packages // {
      ${system} = packages // {
        gred = route packages.gred;
        gr-prod = routeCommands packages.gr-prod;
        gr-dev = routeCommands packages.gr-dev;
        grat = routeCommands packages.grat;
      };
    };
  } else inputs.graphide;
  graphide.autoUpdate = {
    blobAccount = "graphidereleaseswus";
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
    # git stops tracking it (gred/extensions/graphide/out, 2026-09-23): before
    # monolith c3a856832 one dead entry made `git restore` clear nothing.
    allowlist = [
      ".graphide/authored"
      ".agents" ".claude" ".codex" ".cursor"
      "AGENTS.md" "CLAUDE.md" "QUIRKS.md" ".agent-config-manifest" "orca.yaml"
      "gred/.agents" "gred/.claude" "gred/.codex" "gred/.cursor"
      "gred/AGENTS.md" "gred/CLAUDE.md" "gred/QUIRKS.md" "gred/.agent-config-manifest"
      "website/.claude" "website/.codex" "website/.cursor" "website/.agent-config-manifest"
    ];
  };
}
