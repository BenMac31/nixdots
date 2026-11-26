"""Remove idle dependency/build caches while retaining source and test evidence."""

import argparse
from collections import Counter
import fcntl
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import time


def inside(path, root):
    if path == str(root) or path.startswith(str(root) + "/"):
        return True
    if path.startswith("/"):
        try:
            resolved = str(Path(path).resolve())
            canonical_root = str(Path(root).resolve())
            return resolved == canonical_root or resolved.startswith(canonical_root + "/")
        except (OSError, RuntimeError):
            pass
    return False


def project_for(cache):
    for p in cache.parents:
        if (p / ".git").exists():
            return p
        if p == Path.home():
            break
    return cache.parent


def eligible(cache, paths, idle_hours=2, now=None):
    now = time.time() if now is None else now
    if (cache.is_symlink() or not cache.is_dir() or cache.stat().st_ino == 256
            or (cache / ".git").exists()):
        return "not a disposable directory"
    if cache.name == ".venv":
        allowed = {"bin", "include", "lib", "lib64", "share", "pyvenv.cfg",
                   ".gitignore", ".lock", "CACHEDIR.TAG"}
        if not (cache / "pyvenv.cfg").is_file():
            return "unverified virtual environment"
        if any(p.name not in allowed for p in cache.iterdir()):
            return "additional data in environment"
    elif cache.name == "node_modules":
        locks = ("package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lock", "bun.lockb")
        if not ((cache.parent / "package.json").is_file()
                and any((cache.parent / name).is_file() for name in locks)):
            return "no dependency lockfile"
    elif cache.name == "backtest-pg-data":
        recipe = cache.parent / "pg_backtest.sh"
        if not ((cache / "PG_VERSION").is_file() and (cache / "base").is_dir()
                and (cache / "global").is_dir() and recipe.is_file()):
            return "unverified test database"
        script = recipe.read_text()
        if not all(marker in script for marker in
                   ('data="$RUNNER_TEMP/backtest-pg-data"', 'initdb', 'pg_ctl', 'trap', 'fsync=off')):
            return "unverified test database"
        if (cache / "postmaster.pid").exists():
            return "database has a PID marker"
    else:
        return "not a supported cache"
    project = project_for(cache)
    aliases = {str(cache), str(cache.resolve()), str(project), str(project.resolve())}
    if any(inside(p, r) for r in aliases for p in paths):
        return "open project or cache"
    stamps = [cache.stat(), cache.parent.stat()]
    if now - max(max(s.st_mtime, s.st_ctime) for s in stamps) < idle_hours * 3600:
        return "recently changed"
    if (project / ".git").exists():
        tracked = subprocess.check_output(
            ["git", "-c", "core.fsmonitor=false", "-C", str(project), "ls-files",
             "--", str(cache.relative_to(project))],
            env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"), stderr=subprocess.PIPE,
            timeout=60,
        )
        if tracked:
            return "contains tracked source"
    return "eligible"


def prune(cache, paths, idle_hours=2, now=None, dry_run=False):
    reason = eligible(cache, paths, idle_hours, now)
    if reason == "eligible":
        if not dry_run:
            shutil.rmtree(cache)
        return "would remove" if dry_run else "removed"
    return reason


def discover():
    roots = list(dict.fromkeys(str(p.resolve()) for p in (
        Path.home() / "Projects/wt", Path.home() / "Projects/graphide/scratch",
        Path.home() / "Projects/IvorySummit", Path.home() / ".cache",
        Path.home() / ".local/share/agent-scratch/mount/home",
    ) if p.is_dir()))
    if not roots:
        return []
    result = subprocess.run(
        ["find", *roots, "-type", "d", "(", "-name", ".git", "-o", "-name", ".agents",
         "-o", "-name", ".claude", "-o", "-name", ".codex", "-o", "-name", ".stage-*", ")", "-prune", "-o",
         "-type", "d", "(", "-name", ".venv", "-o", "-name", "node_modules",
         "-o", "-name", "backtest-pg-data", ")",
         "-print0", "-prune"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=900)
    if result.returncode and not result.stdout:
        raise subprocess.CalledProcessError(result.returncode, result.args, stderr=result.stderr)
    if result.returncode:
        print("Some paths could not be scanned; each discovered cache will be verified again.", flush=True)
    return [Path(os.fsdecode(p)) for p in result.stdout.split(b"\0") if p]


def cleanup(args, helper):
    counts = Counter()
    paths, checked = helper.active_paths(), time.monotonic()
    for cache in args.roots or discover():
        try:
            if time.monotonic() - checked > 10:
                paths, checked = helper.active_paths(), time.monotonic()
            reason = eligible(cache, paths, args.idle_hours)
            if reason == "eligible":
                reason = prune(cache, paths if args.dry_run else helper.active_paths(),
                               args.idle_hours, dry_run=args.dry_run)
        except (OSError, subprocess.SubprocessError) as error:
            reason = "could not verify or remove"
            print(f"kept {cache}: {error}", flush=True)
        counts[reason] += 1
        if reason in ("removed", "would remove"):
            print(f"{reason} {cache}", flush=True)
        if sum(counts.values()) % 50 == 0:
            print(dict(counts), flush=True)
    print(dict(counts), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--idle-hours", type=float, default=2)
    parser.add_argument("--proc-helper", type=Path, default=Path(__file__).with_name("worktree-prune.py"))
    parser.add_argument("roots", nargs="*", type=Path)
    args = parser.parse_args()
    if args.idle_hours < 1:
        parser.error("idle time must be at least one hour")
    spec = importlib.util.spec_from_file_location("process_paths", args.proc_helper)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    state = Path.home() / ".local/state/disk-watch"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Checkout retirement may remove a cache's parent; serialize both cleanups.
    with (state / "worktree-retirement.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("worktree retirement is running; retry on the next pass", flush=True)
            return
        cleanup(args, helper)


if __name__ == "__main__":
    main()
