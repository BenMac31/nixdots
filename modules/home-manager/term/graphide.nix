{ lib, config, pkgs, inputs, osConfig ? null, flakeAttr ? "nixWorks", ... }:
let
  # DECISION 6: this deliberately skips the per-host anonymous overlay that
  # waybar-pomodoro and yc-cli go through. Those are local pkgs/*.nix files that
  # need callPackage; graphide's flake already exposes finished packages via
  # flake-utils.lib.eachDefaultSystem, so there is nothing to callPackage, and
  # `inputs` is already in extraSpecialArgs. Adding a passthrough line to all
  # five overlay blocks would buy symmetry and nothing else.
  gp = inputs.graphide.packages.${pkgs.stdenv.hostPlatform.system};

  cfg = config.graphide;

  # The exact nix the rest of the machine runs (Lix, per hosts/*/configuration.nix
  # `nix.package`). Falling back to pkgs.nix would put a second, different client
  # in front of the same daemon for no reason.
  nixPackage = if osConfig != null then osConfig.nix.package else pkgs.nix;

  # Same home-manager the flake is evaluated with, not whatever happens to be in
  # ~/.nix-profile -- an auto-switch must not drift from the checkout it switches.
  homeManagerPackage = inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager;

  # Must match `graphide.url` in flake.nix. git+ssh, not `github:`: the repo is
  # private and this machine has no GitHub API token in nix.conf. The systemd
  # user manager carries SSH_AUTH_SOCK and DBUS_SESSION_BUS_ADDRESS, so the
  # service reaches the same agent-held key and the same gh keyring the shell does.
  graphideRepo = "GraphideHQ/monolith";
  graphideGitURL = "git+ssh://git@github.com/graphideHQ/monolith";

  autoUpdateScript = pkgs.writeShellApplication {
    name = "graphide-autoupdate";
    runtimeInputs = [
      nixPackage
      homeManagerPackage
      pkgs.gh
      pkgs.jq
      pkgs.git
      pkgs.openssh
      pkgs.util-linux
      pkgs.libnotify
      pkgs.coreutils
    ];
    text = ''
      FLAKE_DIR=${lib.escapeShellArg cfg.autoUpdate.flakeDir}
      FLAKE_ATTR=${lib.escapeShellArg flakeAttr}
      REPO=${lib.escapeShellArg graphideRepo}
      WORKFLOW=${lib.escapeShellArg cfg.autoUpdate.workflow}
      GIT_URL=${lib.escapeShellArg graphideGitURL}

      fail() {
        echo "graphide-autoupdate: $1" >&2
        notify-send -u critical "Graphide auto-update failed" "$1" || true
        exit 1
      }

      # Only guards against two runs of this service overlapping. A manual
      # `homeswitch` in a shell does not take this lock; nix's own profile and
      # store locks are what keep that case honest.
      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/graphide-autoupdate.lock"
      if ! flock -n 9; then
        echo "graphide-autoupdate: another run holds the lock, skipping"
        exit 0
      fi

      cd "$FLAKE_DIR" || fail "flake directory $FLAKE_DIR is missing"

      current=$(jq -r '.nodes.graphide.locked.rev // empty' flake.lock)
      if [ -z "$current" ]; then
        echo "graphide-autoupdate: flake.lock has no graphide input, nothing to do"
        exit 0
      fi

      # Soft-fail on anything that is just the network or GitHub being unavailable:
      # the timer comes back in ${cfg.autoUpdate.interval}, and a red unit every
      # cycle on a train would be noise, not information.
      # NOT `gh run list --workflow "push gate"`. That resolves the name against
      # the repo's workflow *listing*, which does not contain `push gate` -- gh
      # 2.93 quietly fell back to matching run names, gh 2.99 errors with
      # "could not find any workflows named push gate". Ask for every recent
      # master run and pick the workflow out in jq: version-independent, and one
      # request either way.
      if ! runs=$(gh run list --repo "$REPO" --branch master \
            --json workflowName,headSha,conclusion,createdAt --limit 60 2>&1); then
        echo "graphide-autoupdate: gh lookup failed, will retry next cycle: $runs"
        exit 0
      fi

      green=$(printf '%s' "$runs" \
        | jq -r --arg wf "$WORKFLOW" \
            'map(select(.workflowName == $wf and .conclusion == "success"))
             | sort_by(.createdAt) | reverse | .[0].headSha // empty' 2>/dev/null || true)
      if [ -z "$green" ]; then
        echo "graphide-autoupdate: no successful '$WORKFLOW' run on master in the last 60, skipping"
        exit 0
      fi

      if [ "$green" = "$current" ]; then
        echo "graphide-autoupdate: already up to date at $current"
        exit 0
      fi

      echo "graphide-autoupdate: re-pinning graphide $current -> $green"
      # Local only, on purpose: this rewrites flake.lock in the working tree and
      # never commits or pushes it. The lock in git stays whatever a human put
      # there; `git checkout flake.lock` is the whole undo.
      # --refresh on both calls, and it is load-bearing: nix caches its copy of a
      # dirty git worktree, so a plain `home-manager switch` right after the lock
      # rewrite can be handed the pre-rewrite tree and quietly rebuild the OLD
      # rev. Observed while building this. The locked inputs are content-addressed
      # and already in the store, so --refresh costs a stat, not a re-download.
      if ! nix flake lock --refresh --override-input graphide "$GIT_URL?rev=$green"; then
        fail "could not re-pin flake.lock to $green"
      fi

      # home-manager switch builds before it activates, so a broken commit leaves
      # the current generation running and just fails this unit. That is the
      # correct outcome -- do not wrap it in a rollback.
      if ! home-manager switch --refresh --flake "$FLAKE_DIR#$FLAKE_ATTR"; then
        fail "home-manager switch failed on graphide $green"
      fi

      echo "graphide-autoupdate: switched to graphide $green"
    '';
  };
in
{
  options = {
    graphide = {
      enable = lib.mkEnableOption "Enable Graphide (gr, grat, gred)";
      variant = lib.mkOption {
        type = lib.types.enum [ "dev" "prod" ];
        default = "dev";
        description = ''
          Which gr build to install. DECISION 3: "prod" cannot be built yet --
          gr-prod reads nix/prod-endpoints.nix and refuses while its values
          still start with REPLACE_ME, which they do until the hosted Supabase
          project exists. "dev" bakes the local stack (127.0.0.1:54321 Supabase,
          127.0.0.1:8080 API). Flipping to prod once the endpoints land is one
          word here, not a redesign.
        '';
      };

      autoUpdate = {
        enable = lib.mkEnableOption ''
          a user timer that re-pins the graphide flake input to the newest green
          master commit and switches home-manager onto it. Separate from
          graphide.enable on purpose: unattended re-installation of the editor and
          CLI you are working in is a materially bigger behaviour than having the
          packages, and should be switchable off on its own
        '';

        interval = lib.mkOption {
          type = lib.types.str;
          default = "30m";
          description = "OnUnitActiveSec for the update timer.";
        };

        flakeDir = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/nixos";
          description = "Checkout whose flake.lock is re-pinned and switched.";
        };

        workflow = lib.mkOption {
          type = lib.types.str;
          default = "push gate";
          description = ''
            The GitHub Actions workflow that defines "green". `push gate` is the
            check that actually gates merges to master; `CI / build, vet, test`
            goes red for infra reasons unrelated to code correctness, so keying
            the auto-update on it would stall the update for days at a time.
          '';
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [
        # gr carries grug and grach as siblings in the same bin/ -- the triple is
        # one derivation on purpose, and gred bundles the same variant inside
        # itself so the editor and the CLI cannot point at different stacks.
        (if cfg.variant == "prod" then gp.gr-prod else gp.gr-dev)
        gp.grat
        gp.gred
      ];
    }

    (lib.mkIf cfg.autoUpdate.enable {
      systemd.user.services.graphide-autoupdate = {
        Unit = {
          Description = "Re-pin the graphide flake input to the newest green master commit and switch";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe autoUpdateScript;
          # A nix build should never win a scheduling fight with the editor it is
          # about to replace.
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };

      systemd.user.timers.graphide-autoupdate = {
        Unit.Description = "Check for a newer green graphide master commit";
        Timer = {
          # OnStartupSec, not OnBootSec: this is a user manager, and the first
          # check should land shortly after login rather than after a full
          # interval. Both these and OnUnitActiveSec are CLOCK_BOOTTIME, so a
          # suspended laptop catches up on wake rather than losing the cycle.
          OnStartupSec = "5m";
          OnUnitActiveSec = cfg.autoUpdate.interval;
          RandomizedDelaySec = "2m";
          # No-op for a purely monotonic timer (systemd only honours it for
          # OnCalendar=), kept so it stays correct if this ever moves to one.
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ]);
}
