#!/usr/bin/env python3
"""Grow the mounted scratch image after installing a compatible boot command."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile


GIB = 1024**3
MARKER = "# agent-storage capacity bootstrap"


def command(*argv):
    return subprocess.check_output([str(arg) for arg in argv], text=True).strip()


def check_capacity(info, expected, target, available, minimum):
    if not stat.S_ISREG(info.st_mode) or info.st_size not in {expected, target}:
        raise RuntimeError("scratch must be a regular file with the expected or target size")
    if target <= expected:
        raise RuntimeError("this operation only grows scratch")
    additional = max(0, target - info.st_blocks * 512)
    if available < additional + minimum:
        raise RuntimeError("insufficient host headroom for the bounded increase")
    return additional


def write_file(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".agent-storage-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def grow(args):
    if os.geteuid() != 0:
        raise RuntimeError("run through pkexec")
    expected, target = args.expected_gib * GIB, args.target_gib * GIB
    info = args.image.lstat()
    check_capacity(info, expected, target, shutil.disk_usage(args.image.parent).free,
                   args.minimum_host_free_gib * GIB)
    attrs = dict(line.split("=", 1) for line in command("blkid", "-p", "-o", "export", args.image).splitlines()
                 if "=" in line)
    if attrs.get("TYPE") != "ext4":
        raise RuntimeError("scratch image is not ext4")
    uuid = command("findmnt", "-n", "-o", "UUID", "--mountpoint", args.bulk)
    if uuid != attrs.get("UUID"):
        raise RuntimeError("mounted scratch identity differs from the image")
    loops = json.loads(command("losetup", "--json", "--list", "--associated", args.image,
                               "--output", "NAME"))["loopdevices"]
    if len(loops) != 1:
        raise RuntimeError("expected exactly one scratch loop device")
    device = loops[0]["name"]
    if command("findmnt", "-n", "-o", "SOURCE", "--mountpoint", args.bulk) != device:
        raise RuntimeError("scratch mount is not the expected loop device")
    if not str(args.prepare).startswith("/nix/store/") or not args.prepare.is_file():
        raise RuntimeError("boot preparation must be an immutable Nix-store executable")
    override = Path("/etc/systemd/system.control/agent-storage.service.d/60-capacity.conf")
    if override.exists() and not override.read_text().startswith(MARKER + "\n"):
        raise RuntimeError("an unrecognized capacity override already exists")
    state = Path("/var/lib/agent-storage-resize")
    state.mkdir(mode=0o700, exist_ok=True)
    journal = {"image": str(args.image), "uuid": uuid, "device": device,
               "previous_size": info.st_size, "target_size": target,
               "prepare": str(args.prepare), "phase": "validated"}

    def record(phase):
        journal["phase"] = phase
        write_file(state / "record.json", json.dumps(journal, indent=2) + "\n")

    record("validated")
    command("nix-store", "--realise", args.prepare, "--add-root",
            "/nix/var/nix/gcroots/agent-storage-capacity")
    write_file(override, MARKER + "\n[Service]\nExecStart=\nExecStart=" + str(args.prepare) + "\n")
    command("systemctl", "daemon-reload")
    if str(args.prepare) not in command("systemctl", "show", "agent-storage.service", "-p", "ExecStart", "--value"):
        raise RuntimeError("the compatible boot command was not loaded")
    record("boot-compatible")
    fd = os.open(args.image, os.O_RDWR | os.O_NOFOLLOW)
    try:
        if (os.fstat(fd).st_dev, os.fstat(fd).st_ino) != (info.st_dev, info.st_ino):
            raise RuntimeError("scratch image changed during preparation")
        try:
            os.posix_fallocate(fd, expected, target - expected)
            os.fsync(fd)
        except OSError:
            # The filesystem has not grown yet, so restoring the original
            # file length cannot discard live filesystem blocks.
            os.ftruncate(fd, info.st_size)
            os.fsync(fd)
            raise
    finally:
        os.close(fd)
    record("image-allocated")
    command("losetup", "--set-capacity", device)
    if int(command("blockdev", "--getsize64", device)) != target:
        raise RuntimeError("loop device did not acquire the requested capacity")
    record("device-expanded")
    print(command("resize2fs", device), flush=True)
    if command("findmnt", "-n", "-o", "UUID", "--mountpoint", args.bulk) != uuid:
        raise RuntimeError("scratch identity changed after resize")
    if shutil.disk_usage(args.bulk).total < target * 0.95:
        raise RuntimeError("mounted filesystem did not grow to the target capacity")
    print(command(args.prepare), flush=True)
    record("complete")
    print(json.dumps({"image_gib": args.target_gib, "bulk_free_gib": shutil.disk_usage(args.bulk).free / GIB,
                      "host_free_gib": shutil.disk_usage(args.image.parent).free / GIB,
                      "boot_override": str(override)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", type=Path, required=True)
    parser.add_argument("--image", type=Path, default=Path("/home/greencheetah/.local/share/agent-scratch/store/scratch.img"))
    parser.add_argument("--bulk", type=Path, default=Path("/var/lib/agent-scratch"))
    parser.add_argument("--expected-gib", type=int, default=128)
    parser.add_argument("--target-gib", type=int, default=192)
    parser.add_argument("--minimum-host-free-gib", type=int, default=96)
    parser.add_argument("--tool-path", default="/run/current-system/sw/bin")
    args = parser.parse_args()
    os.environ["PATH"] = args.tool_path
    with Path("/run/lock/agent-storage-resize.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        grow(args)


if __name__ == "__main__":
    main()
