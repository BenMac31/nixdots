{ pkgs, ... }:
let
  # Agents make a worktree per task under ~/Projects/<owner>-wt and park
  # idle ones in <owner>-parked-wt; the worktrees skill forbids them to
  # delete any. On 2026-11-07 that was 2,300 trees and 25M files in a week,
  # and their small files filled btrfs metadata until the laptop hung.
  # A tree goes only when removing it loses nothing: clean, HEAD on an
  # origin branch, not locked, no process inside, idle a day (parked) or
  # three (active). `git worktree remove` keeps the branch and refuses
  # untracked files itself.
  prune = pkgs.writeShellApplication {
    name = "worktree-prune";
    runtimeInputs = [ pkgs.git pkgs.git-lfs pkgs.coreutils pkgs.gnugrep ];
    text = ''
      now=$(date +%s)
      cwds=$(for p in /proc/[0-9]*; do readlink "$p/cwd" 2>/dev/null || true; done)
      inside() { grep -qxF -e "$1" <<<"$cwds" || grep -qF -e "$1/" <<<"$cwds"; }
      removed=0
      for d in "$HOME"/Projects/*-wt/*; do
        case $d in
          */*-parked-wt/*) idle=$((24 * 3600)) ;;
          *) idle=$((72 * 3600)) ;;
        esac
        if [ ! -f "$d/.git" ] || [ -L "$d" ]; then continue; fi
        gd=$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null) || continue
        [ ! -e "$gd/locked" ] || continue
        last=$({ stat -c %Y "$d" "$gd/HEAD" "$gd/index" "$gd/logs/HEAD" 2>/dev/null || true; } | sort -n | tail -1)
        [ $((now - last)) -ge "$idle" ] || continue
        ! inside "$d" || continue
        [ -z "$(GIT_OPTIONAL_LOCKS=0 git -C "$d" status --porcelain 2>/dev/null || echo error)" ] || continue
        [ -n "$(git -C "$d" for-each-ref --contains HEAD --count=1 refs/remotes)" ] || continue
        common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir) || continue
        if git --git-dir="$common" worktree remove "$d"; then
          echo "removed $d"
          removed=$((removed + 1))
        fi
      done
      echo "removed $removed worktrees"
    '';
  };
in
{
  systemd.user.services.worktree-prune = {
    Unit.Description = "Remove agent worktrees that hold nothing unpushed";
    Service = {
      Type = "oneshot";
      ExecStart = "${prune}/bin/worktree-prune";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.worktree-prune = {
    Unit.Description = "Prune idle agent worktrees daily";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
