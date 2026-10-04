{ lib, config, pkgs, ... }:
{
  config = lib.mkIf (config.media.enable && config.desktop.enable) {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "record-mode";
        runtimeInputs = with pkgs; [ coreutils gnugrep systemd ];
        text = ''
          slice=/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/agents.slice
          state="''${XDG_RUNTIME_DIR:?}/record-mode"
          self=$(basename "$(sed -n 's|^0::||p' /proc/self/cgroup)")

          frozen_units() {
            for f in "$slice"/*.scope/cgroup.freeze "$slice"/*.service/cgroup.freeze; do
              if [[ -e $f && $(< "$f") == 1 ]]; then basename "$(dirname "$f")"; fi
            done
          }

          on() {
            if [[ -e $state ]]; then
              echo "record-mode is already on; run 'record-mode off' first" >&2
              exit 1
            fi
            : > "$state"
            for dir in "$slice"/*.scope "$slice"/*.service; do
              [[ -d $dir ]] || continue
              unit=$(basename "$dir")
              case $unit in
                "$self") echo "skip   $unit (the caller)"; continue ;;
                agent-sandbox-*) echo "skip   $unit (editor sandbox)"; continue ;;
              esac
              if systemctl --user freeze "$unit" 2>/dev/null; then
                echo "unit $unit" >> "$state"
                echo "freeze $unit"
              fi
            done
            for unit in localsearch-3.service graphide-autoupdate.service; do
              case $(systemctl --user show -P ActiveState "$unit") in
                active | activating | reloading)
                  if systemctl --user freeze "$unit" 2>/dev/null; then
                    echo "unit $unit" >> "$state"
                    echo "freeze $unit"
                  fi
                  ;;
              esac
            done
            if systemctl --user is-active --quiet graphide-autoupdate.timer; then
              systemctl --user stop graphide-autoupdate.timer
              echo "timer graphide-autoupdate.timer" >> "$state"
              echo "stop   graphide-autoupdate.timer"
            fi
            if pgrep -f '^nix-daemon --for' > /dev/null; then
              echo "warning: nix-daemon is serving a build; record-mode cannot pause it" >&2
            fi
          }

          off() {
            if [[ -e $state ]]; then
              while read -r kind unit; do
                case $kind in
                  unit) systemctl --user thaw "$unit" 2>/dev/null && echo "thaw   $unit" ;;
                  timer) systemctl --user start "$unit" && echo "start  $unit" ;;
                esac
              done < "$state"
              rm -f "$state"
            fi
            for unit in $(frozen_units); do
              systemctl --user thaw "$unit" && echo "thaw   $unit"
            done
          }

          status() {
            if [[ -e $state ]]; then echo "record-mode: on"; else echo "record-mode: off"; fi
            frozen_units | sed 's/^/frozen /'
          }

          case "''${1:-status}" in
            on) on ;;
            off) off ;;
            status) status ;;
            *) echo "usage: record-mode on|off|status" >&2; exit 2 ;;
          esac
        '';
      })
    ];
  };
}
