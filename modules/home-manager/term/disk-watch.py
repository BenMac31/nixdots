"""Keep checking Btrfs headroom while slower cleanup services are busy."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


GIB = 1024**3


def metrics(mount):
    uuid = subprocess.check_output(
        ["findmnt", "-no", "UUID", "-T", mount], text=True, timeout=5
    ).strip()
    fs = Path("/sys/fs/btrfs") / uuid
    if not uuid or not fs.is_dir():
        raise RuntimeError(f"{mount} is not Btrfs")

    def read(path):
        return int((fs / path).read_text())

    size = sum(int(p.read_text()) * 512 for p in fs.glob("devices/*/size"))
    allocated = sum(read(f"allocation/{kind}/disk_total") for kind in ("data", "metadata", "system"))
    stat = os.statvfs(mount)
    total_metadata = read("allocation/metadata/total_bytes")
    return {
        "available_bytes": stat.f_bavail * stat.f_frsize,
        "unallocated_bytes": size - allocated,
        "metadata_used_percent": read("allocation/metadata/bytes_used") * 100 // max(total_metadata, 1),
        "read_only": bool(stat.f_flag & os.ST_RDONLY),
    }


def classify(m):
    if m["read_only"]:
        return "READ_ONLY"
    if (m["available_bytes"] < 192 * GIB or m["unallocated_bytes"] < 24 * GIB
            or (m["metadata_used_percent"] >= 90 and m["unallocated_bytes"] < 32 * GIB)):
        return "CRITICAL"
    if m["available_bytes"] < 256 * GIB or m["unallocated_bytes"] < 48 * GIB:
        return "LOW"
    return "OK"


def ctl(*args):
    return subprocess.run(["systemctl", "--user", *args], check=True, timeout=10, capture_output=True, text=True)


def check(mount, state_dir, reserve, slice_name="agents.slice", dry_run=False, freeze_agents=False):
    m = metrics(mount)
    level = classify(m)
    actions, errors = [], []
    critical = level in ("CRITICAL", "READ_ONLY")
    if critical and freeze_agents:
        try:
            if not dry_run:
                # The watcher runs in background.slice, so freezing agents cannot stop it.
                ctl("freeze", slice_name)
            actions.append(f"froze {slice_name}; thaw manually after freeing space")
        except (OSError, subprocess.SubprocessError) as error:
            errors.append(f"freeze failed: {error}")
    if (critical or m["available_bytes"] < 128 * GIB or m["unallocated_bytes"] < 32 * GIB) and reserve.exists():
        try:
            if not dry_run:
                reserve.unlink()
            actions.append("released emergency reserve")
        except OSError as error:
            errors.append(f"reserve release failed: {error}")
    if level in ("LOW", "CRITICAL") and not dry_run:
        stamp = state_dir / "last-gc"
        if not stamp.exists() or time.time() - stamp.stat().st_mtime >= 3600:
            try:
                state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
                ctl("start", "--no-block", "disk-watch-gc.service")
                stamp.touch()
                actions.append("requested unrooted Nix garbage collection")
            except (OSError, subprocess.SubprocessError) as error:
                errors.append(f"GC request failed: {error}")
    if critical and not dry_run:
        stamp = state_dir / "last-alert"
        if not stamp.exists() or time.time() - stamp.stat().st_mtime >= 3600:
            notifier = shutil.which("notify-send")
            if notifier:
                try:
                    alert = subprocess.run(
                        [notifier, "-a", "disk-watch", "-u", "critical", "Disk space low",
                         f"{m['available_bytes'] / GIB:.1f} GiB available. Storage cleanup is needed."],
                        capture_output=True, text=True, timeout=5,
                    )
                    if alert.returncode == 0:
                        state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
                        stamp.touch()
                        actions.append("sent disk pressure notification")
                except (OSError, subprocess.SubprocessError) as error:
                    print(f"notification failed: {error}", flush=True)
    try:
        frozen = ctl("show", slice_name, "--property=FreezerState", "--value").stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        frozen = "unknown"
        errors.append(f"freeze status failed: {error}")
    result = dict(m, state=level, frozen=frozen, reserve_present=reserve.exists(),
                  automatic_freeze=freeze_agents, updated=int(time.time()), actions=actions, errors=errors)
    if not dry_run:
        try:
            state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
            temporary = state_dir / "state.json.tmp"
            temporary.write_text(json.dumps(result) + "\n")
            temporary.replace(state_dir / "state.json")
        except OSError as error:
            errors.append(f"state write failed: {error}")
    print(json.dumps(result), flush=True)
    if errors:
        raise RuntimeError("; ".join(errors))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mount", default="/")
    parser.add_argument("--state-dir", type=Path, default=Path.home() / ".local/state/disk-watch")
    parser.add_argument("--reserve", type=Path, default=Path.home() / ".local/state/disk-watch-reserve/ballast")
    parser.add_argument("--slice", default="agents.slice")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--freeze-agents", action="store_true",
                        help="opt in to freezing the entire agent slice under critical pressure")
    args = parser.parse_args()
    check(args.mount, args.state_dir, args.reserve, args.slice, args.dry_run, args.freeze_agents)


if __name__ == "__main__":
    main()
