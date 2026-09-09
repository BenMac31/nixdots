{ lib, config, pkgs, inputs, osConfig ? null, flakeAttr ? "nixWorks", ... }:
let
  # DECISION 6: this deliberately skips the per-host anonymous overlay that
  # waybar-pomodoro and yc-cli go through. Those are local pkgs/*.nix files that
  # need callPackage; graphide's flake already exposes finished packages via
  # flake-utils.lib.eachDefaultSystem, so there is nothing to callPackage, and
  # `inputs` is already in extraSpecialArgs. Adding a passthrough line to all
  # five overlay blocks would buy symmetry and nothing else.
  gp = inputs.graphide.packages.${pkgs.stdenv.hostPlatform.system};

  # The endpoint trio the release recipe bakes, read from the SAME file
  # `nix build .#gr-prod` reads, so the wrapper below cannot drift from the
  # build. Do not retype the values here: a hand-copied anon key that goes
  # stale is a binary that 503s on every login and looks perfectly healthy.
  prodEndpoints = import "${inputs.graphide}/nix/prod-endpoints.nix";

  # Pin an installed package's endpoints to the hosted stack, above anything
  # a development tree can do to this machine.
  #
  # grug resolves endpoints in three layers (grug/cmd/grug/main.go,
  # resolveEndpoints): baked ldflags < active config context < GRAPHIDE_*
  # environment. The middle layer is machine-wide -- `active_context` lives in
  # ~/.config/graphide/config.toml and grug's main() calls config.Load(), never
  # LoadForRoot -- so `gr env use local` in ANY checkout repoints every daemon
  # on the box, this one included. Baking prod into the binary is therefore
  # necessary and not sufficient; only the environment layer is out of reach.
  #
  # Deliberately NOT home.sessionVariables. That would export the trio into
  # every shell and drag the development trees to prod as well, which is the
  # exact coupling this exists to remove. It belongs to these binaries only.
  #
  # Caveat worth knowing: a terminal opened INSIDE the installed editor
  # inherits these three, so `gr` run there talks to prod whatever the active
  # context says. Development happens in gred-patch-dev, not in the installed
  # editor, so that is the right trade -- but it is why the variables are set
  # on the wrapper and not on the login shell.
  #
  # cp -as, not symlinkJoin: symlinkJoin links at the highest level it can, so
  # $out/share would itself be a symlink into the store and the desktop files
  # below could not be rewritten. This materialises the directories and
  # symlinks only the leaves.
  pinEndpoints = pkg: exes: pkgs.runCommand "${pkg.pname}-endpoints-pinned"
    {
      nativeBuildInputs = [ pkgs.makeWrapper ];
      meta = pkg.meta or { };
    } ''
      mkdir -p $out
      cp -as ${pkg}/. $out/
      chmod -R u+w $out

      for exe in ${lib.escapeShellArgs exes}; do
        if [ ! -e "$out/bin/$exe" ]; then
          echo "pinEndpoints: ${pkg} has no bin/$exe" >&2
          exit 1
        fi
        target=$(readlink -f "$out/bin/$exe")
        rm "$out/bin/$exe"
        makeWrapper "$target" "$out/bin/$exe" \
          --set GRAPHIDE_API_URL ${lib.escapeShellArg prodEndpoints.apiURL} \
          --set GRAPHIDE_SUPABASE_URL ${lib.escapeShellArg prodEndpoints.supabaseURL} \
          --set GRAPHIDE_SUPABASE_ANON_KEY ${lib.escapeShellArg prodEndpoints.anonKey}
      done

      # A .desktop entry hardcodes the absolute Exec path of the package it was
      # built from, so the launcher -- which is how the editor is actually
      # opened -- would run straight past the wrapper. Repoint them at $out.
      if [ -d "$out/share/applications" ]; then
        for f in "$out"/share/applications/*; do
          src=$(readlink -f "$f")
          rm "$f"
          sed "s|${pkg}/bin/|$out/bin/|g" "$src" > "$f"
        done
      fi
    '';

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
      # No --refresh here or on the switch below. Nix re-reads a dirty worktree on
      # every evaluation -- verified -- so the switch already sees the flake.lock
      # this call just wrote, and --refresh only buys a re-check of every other
      # input in the flake.
      if ! nix flake lock --override-input graphide "$GIT_URL?rev=$green"; then
        fail "could not re-pin flake.lock to $green"
      fi

      # home-manager switch builds before it activates, so a broken commit leaves
      # the current generation running and just fails this unit. That is the
      # correct outcome -- do not wrap it in a rollback.
      if ! home-manager switch --flake "$FLAKE_DIR#$FLAKE_ATTR"; then
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
        default = "prod";
        description = ''
          Which gr build to install. "prod" since 2026-09-09: the hosted
          Supabase project was filled into nix/prod-endpoints.nix on
          2026-09-07, so gr-prod's placeholder assertion passes and the release
          build is buildable. DECISION 3's "cannot be built yet" is spent.

          Why prod rather than dev, now that both point at the hosted stack:
          since monolith 5e3ef19c the SOURCE defaults are the production trio in
          every tier, so gr-dev would reach api.graphide.net too -- by
          inheritance from whatever the source defaults happen to say that week.
          gr-prod injects the trio from nix/prod-endpoints.nix explicitly and
          refuses to build on a placeholder. This is the machine's shipped
          build; its endpoints should be pinned by the release recipe.

          "dev" bakes nothing and is only correct for a checkout working against
          `nix run .#gr-srv`. The local stack is `gr env use local` now, a config
          context rather than a different binary -- but see pinEndpoints above:
          the installed build is deliberately deaf to that context.
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
      home.packages =
        let
          # gr carries grug and grach as siblings in the same bin/ -- the triple
          # is one derivation on purpose, and gred bundles the same variant
          # inside itself so the editor and the CLI cannot point at different
          # stacks.
          grPkg = if cfg.variant == "prod" then gp.gr-prod else gp.gr-dev;

          # Only the prod build is pinned. Wrapping a dev build with the hosted
          # endpoints would be a lie: `variant = "dev"` exists precisely to talk
          # to `nix run .#gr-srv`, and an env pin sits above the context that
          # would point it there.
          pin = if cfg.variant == "prod" then pinEndpoints else (pkg: _exes: pkg);
        in
        [
          # grach takes no endpoints -- the daemon that forks it hands it a
          # gateway and a lease -- so it is not in the wrapped list.
          (pin grPkg [ "gr" "grug" ])
          # gred spawns the grug bundled inside itself, which inherits the
          # editor process's environment, so wrapping the editor covers the
          # bundle. The .desktop rewrite in pinEndpoints is what makes that hold
          # for a launcher start rather than only a terminal one.
          (pin gp.gred [ "gred" ])
          gp.grat
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
