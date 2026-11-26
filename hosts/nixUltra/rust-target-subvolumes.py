"""Keep Cargo build output in nested subvolumes, outside home snapshots."""

import ctypes
import fcntl
import glob
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys


def subvolume(path):
    return path.is_dir() and path.stat().st_ino == 256


def inside(path, root):
    return path == str(root) or path.startswith(str(root) + "/")


def users_of(target):
    users = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            name = (proc / "comm").read_text().strip()
            cwd = os.readlink(proc / "cwd")
            if name in ("cargo", "rustc") and inside(cwd, target.parent):
                users.add(proc.name)
            paths = [cwd, os.readlink(proc / "exe")]
            for fd in (proc / "fd").iterdir():
                try:
                    paths.append(os.readlink(fd))
                except OSError:
                    pass
            if any(inside(p.removesuffix(" (deleted)"), target) for p in paths):
                users.add(proc.name)
            if str(target) + "/" in (proc / "maps").read_text():
                users.add(proc.name)
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            # Some processes are not inspectable; Cargo's artifact locks below
            # provide another check before a directory can be moved.
            continue
    return users


def empty(path):
    for child in path.iterdir():
        if child.is_dir() and not child.is_symlink():
            if subvolume(child):
                raise RuntimeError(f"refusing to remove nested subvolume {child}")
            shutil.rmtree(child)
        else:
            child.unlink()


def create(path):
    subprocess.run(["btrfs", "subvolume", "create", str(path)], check=True)


def exchange(left, right):
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renameat2(-100, os.fsencode(left), -100, os.fsencode(right), 2):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def finish_migration(target, stage):
    marker = target / ".snapshot-exclusion-source.json"
    if not marker.exists():
        return
    if stage.exists() or stage.is_symlink():
        source_stat = stage.lstat()
        expected = json.loads(marker.read_text())
        if stage.is_symlink() or subvolume(stage) or expected != [source_stat.st_dev, source_stat.st_ino]:
            raise RuntimeError(f"unexpected migration directory {stage}")
        if users := users_of(stage):
            print(f"Deferred cleanup of {stage}: in use by {', '.join(sorted(users))}", flush=True)
            return
        shutil.rmtree(stage)
    marker.unlink()


def migrate(target):
    if target.is_symlink():
        return
    stage = target.with_name(".target-snapshot-exclusion")
    if subvolume(target):
        finish_migration(target, stage)
        return
    if not (target.parent / "Cargo.toml").is_file():
        return
    if not target.exists():
        create(target)
        return
    if users := users_of(target):
        print(f"Deferred {target}: in use by {', '.join(sorted(users))}", flush=True)
        return
    locks = []
    try:
        for lock in target.rglob(".cargo-lock"):
            handle = lock.open("r+")
            locks.append(handle)
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if stage.exists() or stage.is_symlink():
            if stage.is_symlink() or not subvolume(stage):
                raise RuntimeError(f"unexpected migration directory {stage}")
            empty(stage)
        else:
            create(stage)
        source_stat = target.stat()
        subprocess.run(["cp", "--archive", "--reflink=always", str(target) + "/.", str(stage)], check=True)
        os.chmod(stage, stat.S_IMODE(source_stat.st_mode))
        # The marker lets a later run finish removing the old directory after
        # an interruption between the atomic swap and cleanup.
        (stage / ".snapshot-exclusion-source.json").write_text(
            json.dumps([source_stat.st_dev, source_stat.st_ino])
        )
        if users := users_of(target):
            empty(stage)
            print(f"Deferred {target}: a build started during copying", flush=True)
            return
        # Both names remain present during the swap. Existing files are cloned,
        # so the migration needs metadata space rather than a second full copy.
        exchange(target, stage)
        print(f"Excluded {target}", flush=True)
        finish_migration(target, stage)
    except BlockingIOError:
        print(f"Deferred {target}: Cargo holds an artifact lock", flush=True)
    finally:
        for handle in locks:
            handle.close()


def discover():
    home = Path.home()
    patterns = [
        "Projects/mic/mods/*/Cargo.toml",
        "Projects/graphide/*/gred-rs/Cargo.toml",
        "Projects/*/gred-rs/Cargo.toml",
    ]
    return sorted({Path(p).parent / "target" for pattern in patterns for p in glob.glob(str(home / pattern))})


def main():
    lock_path = Path.home() / ".cache/rust-target-subvolumes.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        failures = []
        for target in map(Path, sys.argv[1:]) if len(sys.argv) > 1 else discover():
            try:
                migrate(target)
            except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
                failures.append(str(target))
                print(f"Could not exclude {target}: {error}", file=sys.stderr, flush=True)
        if failures:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
