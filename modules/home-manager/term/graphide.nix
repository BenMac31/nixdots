{ lib, config, pkgs, inputs, flakeAttr, ... }:
{
  imports = [ inputs.graphide-tools.homeManagerModules.graphide ];
  graphide.releaseFlake = inputs.graphide;
  graphide.autoUpdate = {
    flakeAttr = flakeAttr;
    homeManagerPackage = inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager;
    sshAuthSock = "%t/ssh-agent";
  };
  graphide.checkoutSync = {
    enable = lib.mkDefault config.graphide.enable;
    checkout = "${config.home.homeDirectory}/Projects/graphide/graphide";
    sshAuthSock = "%t/ssh-agent";
    # The only local state sync may discard: two generated trees plus every
    # agent-config target (listed in each repo's .agent-config-manifest). An
    # `agent-config sync` run in the shared checkout rewrites those in place
    # and used to stall the fast-forward for days (2026-09-15: 146 behind).
    # Directory roots rather than exact files, so a new skill or hook does not
    # re-break it; the cost is that an untracked, non-ignored file a peer drops
    # under one of these dirs is cleaned on the next cycle.
    allowlist = [
      ".graphide/authored" "gred/extensions/graphide/out"
      ".agents" ".claude" ".codex" ".cursor"
      "AGENTS.md" "CLAUDE.md" "QUIRKS.md" ".agent-config-manifest" "orca.yaml"
      "gred/.agents" "gred/.claude" "gred/.codex" "gred/.cursor"
      "gred/AGENTS.md" "gred/CLAUDE.md" "gred/QUIRKS.md" "gred/.agent-config-manifest"
      "website/.claude" "website/.codex" "website/.cursor" "website/.agent-config-manifest"
    ];
  };
}
