{ pkgs, ... }:
# Record why the CPU is pinned below its 400 MHz floor.
#
# Since 2026-09-21 the i7-1185G7 has repeatedly dropped to 200 MHz at ~50 C
# on AC, on battery, and on every charger tried; the EC can hold it for 25+ min.
# That is BD PROCHOT asserted by the EC, not thermal throttling. This logs the
# limit-reason MSRs, battery/AC state and the PD contract on every transition
# into and out of that state, so the next episode names its cause:
#
#   journalctl -u prochot-watch
#
# The watcher only reads; prochot-clear below is the manual override.
let
  watch = pkgs.writeShellApplication {
    name = "prochot-watch";
    runtimeInputs = with pkgs; [ coreutils gawk msr-tools framework-tool ];
    text = ''
      snapshot() {
        echo "cpu kHz: $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | tr '\n' ' ')"
        for r in 0x1FC 0x19C 0x1B1 0x64F; do
          echo "msr $r: $(rdmsr -a -x "$r" | sort -u | tr '\n' ' ')"
        done
        for p in /sys/class/power_supply/*/uevent; do
          echo "$p: $(grep -E 'ONLINE|STATUS|CURRENT_NOW|VOLTAGE_NOW|CAPACITY=' "$p" | tr '\n' ' ')"
        done
        timeout 10 framework_tool --power -vv 2>&1 || true
        timeout 10 framework_tool --pdports 2>&1 || true
      }

      state=0
      while true; do
        khz=$(sort -n /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | tail -1)
        # MSR_CORE_PERF_LIMIT_REASONS bit 0: PROCHOT asserted now.
        prochot=$(( 0x$(rdmsr -p0 -x 0x64F) & 1 ))
        now=0
        if [ "$khz" -lt 390000 ] || [ "$prochot" -eq 1 ]; then now=1; fi
        if [ "$now" -ne "$state" ]; then
          if [ "$now" -eq 1 ]; then
            echo "THROTTLED: max ''${khz} kHz, PROCHOT=$prochot"
          else
            echo "recovered: max ''${khz} kHz"
          fi
          snapshot
          state=$now
        fi
        sleep 5
      done
    '';
  };

  clear = pkgs.writeShellApplication {
    name = "prochot-clear";
    runtimeInputs = with pkgs; [ coreutils msr-tools ];
    text = ''
      for c in $(seq 0 $(($(nproc) - 1))); do
        v=$(rdmsr -p"$c" -d 0x1FC)
        wrmsr -p"$c" 0x1FC $((v & ~1))
      done
      echo "cleared BD PROCHOT; max $(sort -n /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | tail -1) kHz"
    '';
  };
in
{
  hardware.cpu.x86.msr.enable = true;

  systemd.services.prochot-watch = {
    description = "Log EC PROCHOT throttling episodes";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${watch}/bin/prochot-watch";
      Restart = "always";
      RestartSec = 30;
      Nice = 10;
    };
  };

  # Manual escape hatch, bound to CTRL+SUPER+Y. Lasts until reboot or until
  # the EC asserts PROCHOT again.
  systemd.services.prochot-clear = {
    description = "Clear BD PROCHOT on every core";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${clear}/bin/prochot-clear";
    };
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "prochot-clear.service" &&
          action.lookup("verb") == "start" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';
}
