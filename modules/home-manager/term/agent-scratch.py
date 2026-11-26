"""A user-owned, bounded ext4 workspace mounted through UDisks."""

import argparse
import ctypes
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


GIB = 1024**3


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs).stdout.strip()


def create(state, size_gib):
    store = state / "store"
    image = store / "scratch.img"
    if image.exists():
        if image.stat().st_size != size_gib * GIB:
            raise RuntimeError("existing image size differs; refusing to reformat")
        return image
    available = shutil.disk_usage(state).free
    if available < (size_gib + 256) * GIB:
        raise RuntimeError(f"need {size_gib + 256} GiB free before reserving the image")
    if not store.exists():
        run("btrfs", "subvolume", "create", store)
        store.chmod(0o700)
    if store.stat().st_ino != 256:
        raise RuntimeError("image store must be a Btrfs subvolume excluded from snapshots")
    partial = store / "scratch.img.partial"
    if partial.exists():
        raise RuntimeError("an interrupted image creation needs inspection; original file retained")
    with partial.open("xb") as f:
        os.chmod(partial, 0o600)
        run("chattr", "+C", partial)
        os.posix_fallocate(f.fileno(), 0, size_gib * GIB)
        os.fsync(f.fileno())
    run("mkfs.ext4", "-q", "-F", "-m", "0", "-L", "agent-scratch",
        "-E", f"nodiscard,root_owner={os.getuid()}:{os.getgid()}", partial)
    partial.replace(image)
    return image


def mounted(device):
    result = subprocess.run(["findmnt", "--json", "--source", str(device),
                             "--output", "TARGET,FSTYPE,UUID"], capture_output=True, text=True)
    if result.returncode:
        return []
    return json.loads(result.stdout).get("filesystems", [])


def mount(state):
    image = state / "store/scratch.img"
    identity = run("blkid", "-p", "-o", "export", image)
    attrs = dict(line.split("=", 1) for line in identity.splitlines() if "=" in line)
    if attrs.get("TYPE") != "ext4":
        raise RuntimeError("image is not ext4; refusing to mount")
    loops = json.loads(run("losetup", "--json", "--list", "--associated", image, "--output", "NAME"))
    devices = [p["name"] for p in loops.get("loopdevices", [])]
    if len(devices) > 1:
        raise RuntimeError("multiple loop devices reference the image; inspect before mounting")
    if not devices:
        run("udisksctl", "loop-setup", "--no-user-interaction", "--file", image)
        loops = json.loads(run("losetup", "--json", "--list", "--associated", image, "--output", "NAME"))
        devices = [p["name"] for p in loops.get("loopdevices", [])]
    if len(devices) != 1:
        raise RuntimeError("could not identify the image's loop device")
    device = devices[0]
    locations = mounted(device)
    if not locations:
        run("udisksctl", "mount", "--no-user-interaction", "--block-device", device)
        locations = mounted(device)
    valid = [p for p in locations if p.get("fstype") == "ext4" and p.get("uuid") == attrs["UUID"]]
    if not valid:
        raise RuntimeError("mounted filesystem identity does not match the image")
    target = Path(valid[0]["target"])
    if target.stat().st_uid != os.getuid():
        raise RuntimeError("image filesystem is not owned by this account")
    alias = state / "mount"
    if alias.exists() and not alias.is_symlink():
        raise RuntimeError("mount alias contains an existing directory; refusing to replace it")
    stage = state / ".mount.next"
    stage.unlink(missing_ok=True)
    stage.symlink_to(target)
    stage.replace(alias)
    (alias / "home").mkdir(mode=0o700, exist_ok=True)
    (alias / "tmp").mkdir(mode=0o700, exist_ok=True)
    (alias / "tmp" / str(os.getuid())).mkdir(mode=0o700, exist_ok=True)
    return alias


def validate_relative(name):
    p = Path(name)
    if p.is_absolute() or ".." in p.parts or not p.parts or name in ("", "."):
        raise ValueError("workspace paths must be nonempty paths relative to home")
    return p


def busy(root, paths):
    roots = {str(root), str(Path(root).resolve())}
    for path in paths:
        candidates = {path}
        if path.startswith("/"):
            try:
                candidates.add(str(Path(path).resolve()))
            except (OSError, RuntimeError):
                pass
        if any(p == r or p.startswith(r + "/") for p in candidates for r in roots):
            return True
    return False


def exchange(left, right):
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renameat2(-100, os.fsencode(left), -100, os.fsencode(right), 2):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def remove_old(path):
    if path.is_dir() and not path.is_symlink():
        path.chmod(path.stat().st_mode | 0o200)
        for child in list(path.iterdir()):
            remove_old(child)
        try:
            path.rmdir()
        except PermissionError:
            if path.stat().st_ino != 256 or any(path.iterdir()):
                raise
            print(f"empty Btrfs subvolume retained: {path}", flush=True)
    else:
        path.unlink()


def boundary_record(state, relative):
    key = hashlib.sha256(str(relative).encode()).hexdigest()[:16]
    return state / "boundaries" / f"{key}.json"


def redirect_boundary(home, relative, alias, state, apply=False):
    """Route new children to scratch while old children keep their original inodes."""
    relative = validate_relative(str(relative))
    source, destination = home / relative, alias / "home" / relative
    if source.is_symlink():
        return "already capped" if source.resolve() == destination.resolve() else "existing symlink retained"
    if not source.is_dir():
        return "source absent"
    if not apply:
        return "ready to redirect new children; existing data will remain linked"
    destination.mkdir(mode=source.stat().st_mode & 0o777, parents=True, exist_ok=True)
    legacy = source.with_name(f".{source.name}.before-boundary-{time.time_ns()}")
    created = []
    swapped = False
    def bridge_children(root):
        for child in root.iterdir():
            target = destination / child.name
            if os.path.lexists(target):
                if child.resolve() != target.resolve():
                    raise RuntimeError(f"different data already exists at {target}")
            else:
                target.symlink_to(legacy / child.name, target_is_directory=child.is_dir())
                created.append(target)
    try:
        bridge_children(source)
        record = boundary_record(state, relative)
        record.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        record.write_text(json.dumps({"source": str(source), "destination": str(destination),
                                      "legacy": str(legacy)}) + "\n")
        with record.open("rb") as stream:
            os.fsync(stream.fileno())
        legacy.symlink_to(destination)
        exchange(source, legacy)
        swapped = True
        # Include children created while the initial directory listing was built.
        for child in legacy.iterdir():
            target = destination / child.name
            if not os.path.lexists(target):
                target.symlink_to(child, target_is_directory=child.is_dir())
        return f"new children capped; existing data retained at {legacy}"
    finally:
        if not swapped:
            if legacy.is_symlink():
                legacy.unlink()
            for link in created:
                if link.is_symlink():
                    link.unlink()


def managed_bridge(destination, state):
    if not destination.is_symlink():
        return False
    target = destination.resolve()
    for record in (state / "boundaries").glob("*.json"):
        data = json.loads(record.read_text())
        legacy = Path(data["legacy"]).resolve()
        location = destination.parent.resolve() / destination.name
        if target.is_relative_to(legacy) and location.is_relative_to(Path(data["destination"]).resolve()):
            return True
    return False


def migrate_one(home, relative, alias, paths, state, refresh, apply=False, minimum_free_gib=32):
    relative = validate_relative(str(relative))
    source = home / relative
    requested = source
    destination = alias / "home" / relative
    bridge = managed_bridge(destination, state)
    if bridge:
        source = destination.resolve()
    if not bridge and source.exists() and source.resolve() == destination.resolve():
        return "already capped"
    if source.is_symlink():
        if source.resolve() == destination.resolve():
            return "already capped"
        return "existing symlink retained"
    if not source.is_dir():
        return "source absent"
    if busy(requested, paths) or busy(source, paths):
        return "active source retained"
    logical = int(run("du", "--summarize", "--apparent-size", "--block-size=1", source).split()[0])
    free = shutil.disk_usage(alias).free
    if logical + minimum_free_gib * GIB > free:
        return f"does not fit: {logical / GIB:.1f} GiB source, {free / GIB:.1f} GiB free"
    if not apply:
        return f"ready: {logical / GIB:.1f} GiB"
    if not bridge and destination.exists() and any(destination.iterdir()):
        return "existing destination retained; inspect before retrying"
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    records = state / "migrations"
    records.mkdir(mode=0o700, parents=True, exist_ok=True)
    key = hashlib.sha256(str(relative).encode()).hexdigest()[:16]
    stamp = records / f"{key}.checkpoint"
    stamp.touch()
    stage = Path(tempfile.mkdtemp(prefix=f".stage-{source.name}-", dir=destination.parent))
    try:
        run("rsync", "-aHAX", "--numeric-ids", str(source) + "/", str(stage) + "/")
        differences = run("rsync", "-aHAXnc", "--numeric-ids", "--delete", "--itemize-changes",
                          str(source) + "/", str(stage) + "/")
        if differences:
            return "source changed during copy; original retained"
        current_paths = refresh()
        if busy(requested, current_paths) or busy(source, current_paths):
            return "source became active; original retained"
        run("sync", "-f", stage)
        if bridge:
            exchange(stage, destination)
            stage.unlink()
        else:
            stage.replace(destination)
    finally:
        if stage.exists():
            remove_old(stage)
    backup = source if bridge else source.with_name(f".{source.name}.pre-scratch-{time.time_ns()}")
    if not bridge:
        backup.symlink_to(destination)
        exchange(source, backup)
    record = records / f"{key}.json"
    record.write_text(json.dumps({"source": str(source), "destination": str(destination),
                                  "backup": str(backup), "verified": True}) + "\n")
    with record.open("rb") as f:
        os.fsync(f.fileno())
    if busy(backup, refresh()):
        return f"capped; old copy still open and retained at {backup}"
    changed = run("find", backup, "-mindepth", "1", "-cnewer", stamp, "-print", "-quit")
    if changed:
        return f"capped; old copy changed and retained at {backup}"
    remove_old(backup)
    return "capped; verified old data removed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, default=Path.home() / ".local/share/agent-scratch")
    parser.add_argument("--size-gib", type=int, default=128)
    parser.add_argument("--minimum-free-gib", type=int, default=32)
    parser.add_argument("--proc-helper", type=Path, default=Path(__file__).with_name("worktree-prune.py"))
    parser.add_argument("--path", action="append", default=[])
    parser.add_argument("--boundary", action="append", default=[])
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--children", action="store_true", help="retry individual directories when a parent cannot move")
    parser.add_argument("--limit", type=int, default=4, help="maximum successful migrations in one pass")
    parser.add_argument("action", choices=["create", "mount", "plan", "migrate", "boundary"])
    args = parser.parse_args()
    if args.size_gib < 1:
        parser.error("image size must be positive")
    args.state.mkdir(mode=0o700, parents=True, exist_ok=True)
    def interrupted(_signum, _frame):
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, interrupted)
    with (args.state / "setup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == "create":
            print(create(args.state, args.size_gib), flush=True)
        elif args.action == "mount":
            print(mount(args.state), flush=True)
        else:
            spec = importlib.util.spec_from_file_location("paths", args.proc_helper)
            helper = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(helper)
            alias = mount(args.state)
            if args.action == "boundary":
                for name in args.boundary:
                    try:
                        print(f"{name}: {redirect_boundary(Path.home(), name, alias, args.state, args.apply)}", flush=True)
                    except (OSError, RuntimeError) as error:
                        print(f"{name}: original retained: {error}", flush=True)
                return
            paths = helper.active_paths()
            completed = 0
            queue = list(args.path)
            while queue:
                name = queue.pop(0)
                try:
                    result = migrate_one(Path.home(), name, alias, paths, args.state,
                                         helper.active_paths, args.action == "migrate" and args.apply,
                                         args.minimum_free_gib)
                except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                    result = f"retained after error: {error}"
                print(f"{name}: {result}", flush=True)
                if result.startswith("capped;"):
                    completed += 1
                    if completed >= args.limit:
                        break
                elif args.children and name in args.path and result != "source absent":
                    source = Path.home() / name
                    if source.is_dir():
                        queue.extend(str(child.relative_to(Path.home())) for child in sorted(source.iterdir())
                                     if child.is_dir() and not child.name.startswith("."))
                paths = helper.active_paths()


if __name__ == "__main__":
    main()
