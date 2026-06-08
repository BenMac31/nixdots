{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.healthAlerts;

  cacheDir = "${config.home.homeDirectory}/.cache/system-health";

  nixpkgsChannel =
    let
      lock = builtins.fromJSON (builtins.readFile "${inputs.self}/flake.lock");
      nixpkgsNode = lock.nodes.root.inputs.nixpkgs;
      ref = lock.nodes.${nixpkgsNode}.original.ref or "";
    in
    if lib.hasPrefix "nixos-" ref then ref else null;

  batteryScript = pkgs.writeShellScript "health-alerts-battery" ''
    set -eu

    WARN=${toString cfg.battery.warnPercent}
    CRIT=${toString cfg.battery.critPercent}
    URGENT=${toString cfg.battery.urgentPercent}
    HYSTERESIS=5

    STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/health-alerts"
    mkdir -p "$STATE_DIR"
    STATE_FILE="$STATE_DIR/battery"

    battery_path=$(${pkgs.upower}/bin/upower -e | ${pkgs.gnugrep}/bin/grep -m1 'battery' || true)
    if [ -z "$battery_path" ]; then
      exit 0
    fi

    get_pct() {
      ${pkgs.upower}/bin/upower -i "$battery_path" | ${pkgs.gawk}/bin/awk '/percentage:/ { print int($2); exit }'
    }

    get_state() {
      ${pkgs.upower}/bin/upower -i "$battery_path" | ${pkgs.gawk}/bin/awk -F: '/state:/ { gsub(/ /, "", $2); print $2; exit }'
    }

    clear_alert() {
      rm -f "$STATE_FILE"
    }

    maybe_alert() {
      level=$1
      pct=$2
      message=$3
      last_level=""
      if [ -f "$STATE_FILE" ]; then
        read -r last_level < "$STATE_FILE" || true
      fi
      if [ "$last_level" = "$level" ]; then
        return
      fi
      urgency=normal
      if [ "$level" != "warning" ]; then
        urgency=critical
      fi
      ${pkgs.libnotify}/bin/notify-send -u "$urgency" "Battery ''${level}" "$message ($pct%)"
      echo "$level" > "$STATE_FILE"
    }

    check_battery() {
      state=$(get_state)
      case "$state" in
        charging | fully-charged | pending-charge)
          clear_alert
          return
          ;;
      esac

      pct=$(get_pct)
      last_level=""
      if [ -f "$STATE_FILE" ]; then
        read -r last_level < "$STATE_FILE" || true
      fi

      if [ "$pct" -ge $((URGENT + HYSTERESIS)) ] && [ "$last_level" = "urgent" ]; then
        clear_alert
        last_level=""
      fi
      if [ "$pct" -ge $((CRIT + HYSTERESIS)) ] && [ "$last_level" = "critical" ]; then
        clear_alert
        last_level=""
      fi
      if [ "$pct" -ge $((WARN + HYSTERESIS)) ] && [ "$last_level" = "warning" ]; then
        clear_alert
        last_level=""
      fi

      if [ "$pct" -le "$URGENT" ]; then
        maybe_alert urgent "$pct" "Battery critically low — plug in soon"
      elif [ "$pct" -le "$CRIT" ]; then
        maybe_alert critical "$pct" "Battery low"
      elif [ "$pct" -le "$WARN" ]; then
        maybe_alert warning "$pct" "Battery getting low"
      fi
    }

    check_battery

    ${pkgs.dbus}/bin/dbus-monitor --system \
      "type='signal',interface='org.freedesktop.UPower.Device',member='Changed',path='$battery_path'" \
      | while read -r _; do
          check_battery
        done
  '';

  diskScript = pkgs.writeShellScript "health-alerts-disk" ''
    set -eu

    CACHE_DIR="${cacheDir}"
    WARN_FILE="$CACHE_DIR/disk-warning"
    WARN_PCT=${toString cfg.disk.warnPercent}
    CRIT_PCT=${toString cfg.disk.critPercent}

    mkdir -p "$CACHE_DIR"

    warnings=""
    for mount in / /nix; do
      if ! pct=$(${pkgs.coreutils}/bin/df --output=pcent "$mount" 2>/dev/null | ${pkgs.coreutils}/bin/tail -1 | tr -dc '0-9'); then
        continue
      fi
      if [ "$pct" -ge "$CRIT_PCT" ]; then
        warnings="''${warnings}CRITICAL: $mount is ''${pct}% full (threshold: ''${CRIT_PCT}%)\n"
      elif [ "$pct" -ge "$WARN_PCT" ]; then
        warnings="''${warnings}WARNING: $mount is ''${pct}% full (threshold: ''${WARN_PCT}%)\n"
      fi
    done

    if [ -n "$warnings" ]; then
      printf '%b' "$warnings" > "$WARN_FILE"
    else
      rm -f "$WARN_FILE"
    fi
  '';

  releaseScript =
    if nixpkgsChannel == null then
      pkgs.writeShellScript "health-alerts-release" "exit 0"
    else
      pkgs.writeShellScript "health-alerts-release" ''
        set -eu

        CHANNEL="${nixpkgsChannel}"
        CACHE_DIR="${cacheDir}"
        WARN_FILE="$CACHE_DIR/release-warning"

        mkdir -p "$CACHE_DIR"

        if ! data=$(${pkgs.curl}/bin/curl -sf 'https://prometheus.nixos.org/api/v1/query?query=channel_revision'); then
          exit 0
        fi

        status=$(${pkgs.jq}/bin/jq -r --arg ch "$CHANNEL" \
          '.data.result[] | select(.metric.channel == $ch) | .metric.status' <<< "$data" | ${pkgs.coreutils}/bin/head -1)

        case "$status" in
          stable | rolling | "")
            rm -f "$WARN_FILE"
            exit 0
            ;;
        esac

        ver="''${CHANNEL#nixos-}"
        yy="''${ver%%.*}"
        mm="''${ver##*.}"
        yyyy=$((2000 + yy))
        if [ "$mm" = "05" ]; then
          eol_date="''${yyyy}-12-31"
        elif [ "$mm" = "11" ]; then
          eol_date="$((yyyy + 1))-06-30"
        else
          eol_date="unknown (see release notes)"
        fi

        status_label=$(printf '%s' "$status" | tr '[:lower:]' '[:upper:]')

        {
          printf '%s\n' \
            "╔══════════════════════════════════════════════════════════════╗" \
            "║  WARNING: NixOS $ver is $status_label" \
            "║  Channel: $CHANNEL" \
            "║  Security support ends: $eol_date" \
            "║  Upgrade: cd ~/nixos && nix flake lock --update-input nixpkgs && nixswitch" \
            "║  https://nixos.org/manual/nixos/stable/index.html#sec-upgrading" \
            "╚══════════════════════════════════════════════════════════════╝"
        } > "$WARN_FILE"
      '';
in
{
  options.healthAlerts = {
    enable = lib.mkEnableOption "Laptop system health alerts (battery, disk, release deprecation)";

    disk = {
      warnPercent = lib.mkOption {
        type = lib.types.int;
        default = 90;
        description = "Disk usage percentage that triggers a terminal warning.";
      };
      critPercent = lib.mkOption {
        type = lib.types.int;
        default = 95;
        description = "Disk usage percentage that triggers a critical terminal warning.";
      };
    };

    battery = {
      warnPercent = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Battery percentage for a desktop notification.";
      };
      critPercent = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = "Battery percentage for a critical desktop notification.";
      };
      urgentPercent = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Battery percentage for an urgent desktop notification.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.health-alerts-battery = {
      Unit = {
        Description = "Battery low alerts via UPower";
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${batteryScript}";
        Restart = "always";
        RestartSec = "10";
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.health-alerts-disk = {
      Unit = {
        Description = "Check disk space and update terminal warning cache";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${diskScript}";
      };
    };

    systemd.user.timers.health-alerts-disk = {
      Unit = {
        Description = "Daily disk space check";
      };
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.health-alerts-release = {
      Unit = {
        Description = "Check NixOS release deprecation and update terminal warning cache";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${releaseScript}";
      };
    };

    systemd.user.timers.health-alerts-release = {
      Unit = {
        Description = "Weekly NixOS release deprecation check";
      };
      Timer = {
        OnCalendar = "Mon *-*-* 09:00:00";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    programs.zsh.initExtra = lib.mkIf config.programs.zsh.enable (
      lib.mkAfter /*bash*/ ''
        system_health_cache="$HOME/.cache/system-health"
        if [[ -d "$system_health_cache" ]]; then
          for warning_file in "$system_health_cache"/*-warning(N); do
            print -P "%F{red}$(<"$warning_file")%f" >&2
          done
        fi
      ''
    );
  };
}
