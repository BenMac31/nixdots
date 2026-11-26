#!/usr/bin/env python3
"""Require a reboot when changing the system's temporary mounts."""

from pathlib import Path
import sys


def temporary_mounts(fstab):
    mounts = {}
    for line in fstab.splitlines():
        fields = line.split()
        if not fields or fields[0].startswith("#"):
            continue
        if len(fields) >= 4 and fields[1] in {"/tmp", "/var/tmp"}:
            mounts[fields[1]] = (fields[0], fields[2], tuple(sorted(fields[3].split(","))))
    return mounts


def check(incoming, action, current=Path("/run/current-system"), fstab=Path("/etc/fstab")):
    if action in {"boot", "dry-activate"}:
        return
    unit = "etc/systemd/system/agent-storage.service"
    if not (current / unit).exists() and not (incoming / unit).exists():
        return
    old = temporary_mounts(fstab.read_text())
    new = temporary_mounts((incoming / "etc/fstab").read_text())
    if old != new:
        raise RuntimeError(
            "Refusing live activation: /tmp or /var/tmp mounts would change. "
            "Their dependents include D-Bus and basic.target. "
            "Use nixos-rebuild boot and reboot when your work is saved; "
            "nixos-rebuild test also changes the running system."
        )


if __name__ == "__main__":
    try:
        check(Path(sys.argv[1]), sys.argv[2])
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
