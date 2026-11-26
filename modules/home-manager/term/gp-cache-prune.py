"""Remove old, unused registry mirrors without losing unpublished work."""

import argparse
import fcntl
import getpass
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


AGE = 48 * 3600


def git(root, *args):
    return subprocess.check_output(
        ["git", "-c", "core.fsmonitor=false", "-C", str(root), *args],
        text=True, stderr=subprocess.DEVNULL, timeout=30,
        env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"),
    ).strip()


def last_use(root):
    paths = [root, root / ".git", *(root / ".git" / p for p in
             ("FETCH_HEAD", "HEAD", "index", "logs/HEAD"))]
    return max(p.stat().st_mtime for p in paths if p.exists())


def active_paths():
    paths = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            paths.add(os.readlink(proc / "cwd"))
            for fd in (proc / "fd").iterdir():
                try:
                    paths.add(os.readlink(fd).removesuffix(" (deleted)"))
                except OSError:
                    pass
        except (OSError, ProcessLookupError):
            continue
    return paths


def prune(root, paths, now=None, dry_run=False, age=AGE):
    now = time.time() if now is None else now
    if (root.is_symlink() or not root.is_dir() or root.stat().st_ino == 256
            or (root / ".git").is_symlink() or not (root / ".git").is_dir()):
        return "not a disposable clone"
    if now - last_use(root) < age:
        return "recently used"
    aliases = {str(root), str(root.resolve())}
    normalized = set(paths)
    for path in paths:
        if path.startswith("/"):
            try:
                normalized.add(str(Path(path).resolve()))
            except (OSError, RuntimeError):
                pass
    if any(p == r or p.startswith(r + "/") for p in normalized for r in aliases):
        return "open by a process"

    # gp holds this same sidecar flock for the entire lifetime of a command.
    # Keep the lock file after cleanup so waiting callers still share its inode.
    with root.with_name(root.name + ".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return "in use by gp"
        if now - last_use(root) < age:
            return "recently used"
        if any((root / ".git").rglob("*.lock")):
            return "Git operation in progress"
        if any((root / ".git" / name).exists() for name in
               ("rebase-merge", "rebase-apply", "sequencer", "MERGE_HEAD",
                "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG", "gc.pid")):
            return "Git operation in progress"
        worktrees = root / ".git/worktrees"
        if worktrees.exists() and any(worktrees.iterdir()):
            return "has worktrees"
        common = Path(git(root, "rev-parse", "--git-common-dir"))
        if not common.is_absolute():
            common = root / common
        if common.resolve() != (root / ".git").resolve():
            return "shared Git directory"
        if git(root, "for-each-ref", "--format=%(refname)", "refs/archive/disk-budget"):
            return "has recovery refs"
        if git(root, "status", "--porcelain", "--untracked-files=all"):
            return "local changes"
        if git(root, "stash", "list", "--format=%H"):
            return "has stashes"
        if not git(root, "remote"):
            return "no remote"
        if not git(root, "for-each-ref", "--format=%(refname)", "refs/remotes"):
            return "no published history"
        if git(root, "rev-list", "--all", "--not", "--remotes", "--max-count=1"):
            return "unpublished commits"
        if not dry_run:
            shutil.rmtree(root)
        return "would remove" if dry_run else "removed"


def primary_identities(cache_roots):
    identities = set()
    for cache in cache_roots:
        primary = cache / "gp" / f"registry-{getpass.getuser()}"
        try:
            info = primary.stat()
            identities.add((info.st_dev, info.st_ino))
        except FileNotFoundError:
            pass
    return identities


def discover(cache_roots, temporary_roots=()):
    """Inspect only known gp namespaces, without traversing workspace contents."""
    seen = set()
    cache_roots = tuple(cache_roots)
    protected = primary_identities(cache_roots)
    namespaces = []
    for cache in cache_roots:
        namespaces.extend([cache / "gp", *sorted(cache.glob("gp-*"))])
    for temporary in temporary_roots:
        if not temporary.is_dir():
            continue
        # gp also accepts arbitrary temporary namespace names. Its sidecar
        # lifetime lock distinguishes these from unrelated checkout folders.
        for namespace in temporary.iterdir():
            if namespace.is_dir() and not namespace.is_symlink() and any(namespace.glob("registry-*.lock")):
                namespaces.append(namespace)
        for pattern in ("*/gp", "*/gp-*", "*/gpcache"):
            namespaces.extend(sorted(temporary.glob(pattern)))
    for namespace in namespaces:
        if namespace.is_dir():
            for root in sorted(namespace.glob("registry-*")):
                if not root.is_dir():
                    continue
                info = root.stat()
                identity = (info.st_dev, info.st_ino)
                if identity not in seen and identity not in protected:
                    seen.add(identity)
                    yield root


def retention_age(pressure_path, free_gib, idle_hours, critical_free_gib=0):
    if pressure_path is None:
        return AGE
    free = shutil.disk_usage(pressure_path).free
    if free < critical_free_gib * 1024**3:
        return 0
    if free < free_gib * 1024**3:
        return idle_hours * 3600
    return AGE


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, help="inspect only this gp namespace")
    parser.add_argument("--cache-root", type=Path, action="append")
    parser.add_argument("--temporary-root", type=Path, action="append", default=[])
    parser.add_argument("--pressure-path", type=Path)
    parser.add_argument("--pressure-free-gib", type=float, default=32)
    parser.add_argument("--critical-free-gib", type=float, default=24)
    parser.add_argument("--pressure-idle-hours", type=float, default=6)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.pressure_idle_hours < 1 or args.pressure_free_gib <= 0:
        parser.error("pressure idle time must be at least one hour and headroom must be positive")
    if not 0 <= args.critical_free_gib < args.pressure_free_gib:
        parser.error("critical headroom must be nonnegative and below pressure headroom")
    age = retention_age(args.pressure_path, args.pressure_free_gib, args.pressure_idle_hours,
                        args.critical_free_gib)
    print(json.dumps({"minimum_idle_hours": age / 3600, "dry_run": args.dry_run}), flush=True)
    paths = active_paths()
    counts = {}
    cache_roots = args.cache_root or [Path.home() / ".cache"]
    protected = primary_identities(cache_roots)
    roots = (sorted(args.cache.glob("registry-*")) if args.cache else
             discover(cache_roots, args.temporary_root))
    checked = time.monotonic()
    for root in roots:
        # Stop emergency eviction once headroom returns, preserving warm mirrors.
        if age == 0 and shutil.disk_usage(args.pressure_path).free >= args.pressure_free_gib * 1024**3:
            break
        if not root.is_dir():
            continue
        try:
            info = root.stat()
        except FileNotFoundError:
            continue
        if (info.st_dev, info.st_ino) in protected:
            continue
        try:
            if time.monotonic() - checked > 5:
                paths, checked = active_paths(), time.monotonic()
            reason = prune(root, paths, dry_run=True, age=age)
            if reason == "would remove" and not args.dry_run:
                reason = prune(root, active_paths(), age=age)
        except (OSError, subprocess.SubprocessError) as error:
            reason = "could not verify"
            print(f"kept {root}: {type(error).__name__}", flush=True)
        counts[reason] = counts.get(reason, 0) + 1
        if reason in ("removed", "would remove"):
            print(f"{reason} {root}", flush=True)
    print(counts, flush=True)


if __name__ == "__main__":
    main()
