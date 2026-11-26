"""Retire idle, published Git worktrees without removing their branches."""

import argparse
from collections import Counter
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import time


BUILD_DIRS = {"node_modules", "target", ".venv", "__pycache__", ".pytest_cache",
              ".mypy_cache", ".ruff_cache", ".direnv", ".gradle", ".next",
              ".turbo", ".parcel-cache"}


def git(root, *args, timeout=60):
    return subprocess.check_output(
        ["git", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
         "-C", str(root), *args],
        env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"), text=True,
        stderr=subprocess.PIPE, timeout=timeout,
    ).strip()


def active_paths():
    paths = set()
    sockets = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            name = (proc / "comm").read_text().strip()
            if name in ("go", "compile", "link", "asm"):
                paths.add(str(Path.home() / ".cache/go-build"))
            if name in ("cargo", "rustc", "sccache"):
                paths.add(str(Path.home() / ".cache/gred-rs"))
            for name in ("cwd", "exe"):
                try:
                    paths.add(os.readlink(proc / name).removesuffix(" (deleted)"))
                except OSError:
                    pass
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd).removesuffix(" (deleted)")
                    paths.add(target)
                    if target.startswith("socket:["):
                        sockets.add(target[8:-1])
                except OSError:
                    pass
            for line in (proc / "maps").read_text().splitlines():
                fields = line.split(maxsplit=5)
                if len(fields) == 6 and fields[5].startswith("/"):
                    paths.add(fields[5].removesuffix(" (deleted)"))
            for arg in (proc / "cmdline").read_bytes().split(b"\0"):
                if arg.startswith(b"/"):
                    paths.add(os.fsdecode(arg))
            for item in (proc / "environ").read_bytes().split(b"\0"):
                if item.startswith(b"VIRTUAL_ENV=/"):
                    paths.add(os.fsdecode(item.split(b"=", 1)[1]))
        except (OSError, ProcessLookupError):
            continue
    try:
        for line in Path("/proc/net/unix").read_text().splitlines()[1:]:
            fields = line.split(maxsplit=7)
            if len(fields) == 8 and fields[6] in sockets and fields[7].startswith("/"):
                paths.add(fields[7])
    except OSError:
        pass
    try:
        for line in Path("/proc/self/mountinfo").read_text().splitlines():
            target = line.split()[4]
            paths.add(re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), target))
    except OSError:
        pass
    return paths


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


def discover(home):
    commons = set()
    patterns = ["Projects/" + "*/" * depth + ".git" for depth in range(1, 5)]
    for pattern in [*patterns, "graphide-*/.git"]:
        for dotgit in home.glob(pattern):
            try:
                common = dotgit
                if dotgit.is_file():
                    pointer = dotgit.read_text().strip()
                    if not pointer.startswith("gitdir: "):
                        continue
                    gd = Path(pointer.removeprefix("gitdir: "))
                    if not gd.is_absolute():
                        gd = dotgit.parent / gd
                    common = gd / (gd / "commondir").read_text().strip()
                if (common / "worktrees").is_dir():
                    commons.add(common.resolve())
            except OSError:
                continue
    roots = set()
    for common in commons:
        for link in (common / "worktrees").glob("*/gitdir"):
            try:
                root = Path(link.read_text().strip()).parent
                if root.is_relative_to(home / "Projects") and root.is_dir():
                    roots.add(root)
            except OSError:
                continue
    return sorted(roots)


def inspect(root, paths, idle_hours, now=None, allow_local_changes=False, allow_unpublished=False):
    now = time.time() if now is None else now
    if root.is_symlink() or not (root / ".git").is_file():
        return "not a linked worktree", None
    aliases = {str(root), str(root.resolve())}
    if any(inside(p, r) for r in aliases for p in paths):
        return "open by a process", None
    gd = Path(git(root, "rev-parse", "--absolute-git-dir"))
    if (gd / "locked").exists():
        return "locked", None
    common = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir"))
    if not gd.is_relative_to(common / "worktrees"):
        return "not a linked worktree", None
    stamps = [root, gd / "HEAD", gd / "index", gd / "logs/HEAD"]
    if now - max(p.stat().st_mtime for p in stamps if p.exists()) < idle_hours * 3600:
        return "recently used", None
    if any(gd.glob("*.lock")) or any(common.glob("*.lock")):
        return "Git operation in progress", None
    if any((gd / name).exists() for name in
           ("rebase-merge", "rebase-apply", "sequencer", "MERGE_HEAD",
            "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG")):
        return "Git operation in progress", None
    dirty = git(root, "status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none")
    if dirty and not allow_local_changes:
        return "local changes", None
    ignored = git(root, "ls-files", "--others", "--ignored", "--exclude-standard",
                  "--directory", "--no-empty-directory", "-z")
    keep = [name for name in ignored.split("\0")
            if name and not BUILD_DIRS.intersection(Path(name).parts)]
    head = git(root, "rev-parse", "HEAD")
    published = git(root, "for-each-ref", "--contains", head, "--count=1", "--format=%(refname)", "refs/remotes")
    if not published and not allow_unpublished:
        return "unpublished commits", None
    return "eligible", {"path": str(root), "head": head,
                         "published_ref": published, "common": str(common),
                         "ignored": keep, "dirty": dirty}


def archive_head(root, record, archive_dir):
    archive_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    objects = git(root, "rev-list", "--objects", "--no-object-names", "HEAD", "--not", "--remotes")
    sizes = subprocess.check_output(
        ["git", "-C", str(root), "cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)"],
        input=(objects + "\n").encode(), stderr=subprocess.PIPE, timeout=60)
    for line in sizes.splitlines():
        oid, kind, size = line.split()
        if kind == b"blob" and int(size) <= 1024:
            data = subprocess.check_output(["git", "-C", str(root), "cat-file", "blob", oid.decode()],
                                           stderr=subprocess.PIPE, timeout=60)
            if data.startswith(b"version https://git-lfs.github.com/spec/v1\n"):
                raise RuntimeError("unpublished LFS objects must be retained in place")
    required = int(git(root, "rev-list", "--disk-usage", "--objects", "HEAD", "--not", "--remotes"))
    space = os.statvfs(archive_dir)
    if required + 64 * 1024**3 > space.f_bavail * space.f_frsize:
        raise RuntimeError("insufficient headroom to bundle commits safely")
    key = hashlib.sha256((record["common"] + record["head"]).encode()).hexdigest()[:24]
    bundle = archive_dir / f"unpublished-{key}.bundle"
    if not bundle.exists():
        partial = bundle.with_suffix(".partial")
        try:
            git(root, "bundle", "create", str(partial), "HEAD", "--not", "--remotes", timeout=1800)
            partial.chmod(0o600)
            partial.replace(bundle)
        finally:
            partial.unlink(missing_ok=True)
    prerequisites = git(root, "bundle", "verify", str(bundle))
    if git(root, "bundle", "list-heads", str(bundle), "HEAD").split()[0] != record["head"]:
        raise RuntimeError("bundle HEAD does not match the worktree")
    # The recovery ref also retains every base object required by the bundle.
    ref = f"refs/archive/disk-budget/{record['head']}"
    git(root, "update-ref", ref, record["head"])
    with bundle.open("rb") as f:
        os.fsync(f.fileno())
    record.update(commit_bundle=str(bundle), recovery_ref=ref, bundle_prerequisites=prerequisites)


def fingerprint(root, names):
    result = {}
    def visit(path):
        s = path.lstat()
        if not (stat.S_ISREG(s.st_mode) or stat.S_ISDIR(s.st_mode) or stat.S_ISLNK(s.st_mode)):
            raise RuntimeError("special files must be retained in place")
        result[str(path.relative_to(root))] = [s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns]
        if path.is_dir() and not path.is_symlink():
            if ((path / ".git").exists()
                    or ((path / "objects").is_dir()
                        and ((path / "worktrees").is_dir() or (path / "refs").is_dir()))):
                raise RuntimeError("nested Git repository must be retained in place")
            for child in path.iterdir():
                visit(child)
    for name in names:
        p = Path(name)
        if p.is_absolute() or ".." in p.parts:
            raise RuntimeError("unexpected ignored path")
        visit(root / p)
    return result


def archive_ignored(root, record, archive_dir):
    archive_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    before = fingerprint(root, record["ignored"])
    tag = hashlib.sha256((str(root) + json.dumps(before, sort_keys=True)).encode()).hexdigest()[:24]
    dest = archive_dir / f"{root.name}-{tag}.tar.zst"
    if not dest.exists():
        partial = dest.with_suffix(".partial")
        try:
            with tempfile.NamedTemporaryFile(dir=archive_dir) as listing:
                listing.write(b"".join(os.fsencode(name) + b"\0" for name in record["ignored"]))
                listing.flush()
                subprocess.run(
                    ["tar", "--create", "--file", str(partial), "--use-compress-program=zstd -q -T1 -3",
                     "--directory", str(root), "--null", "--verbatim-files-from", "--files-from", listing.name],
                    check=True, capture_output=True, timeout=1800,
                )
            os.chmod(partial, 0o600)
            partial.replace(dest)
        finally:
            partial.unlink(missing_ok=True)
    subprocess.run(["tar", "--compare", "--file", str(dest), "--use-compress-program=zstd -q -d",
                    "--directory", str(root)], check=True, capture_output=True, timeout=1800)
    if before != fingerprint(root, record["ignored"]):
        raise RuntimeError("ignored files changed during archiving; worktree kept")
    with dest.open("rb") as archive:
        os.fsync(archive.fileno())
    record["archive"] = str(dest)
    return before


def local_state(root, record):
    def raw(*args):
        return subprocess.check_output(
            ["git", "-c", "core.fsmonitor=false", "-C", str(root), *args],
            env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"), stderr=subprocess.PIPE, timeout=60)
    if any(line.startswith("160000 ") for line in git(root, "ls-files", "--stage").splitlines()):
        raise RuntimeError("submodule state must be retained in place")
    tracked = [os.fsdecode(p) for p in raw("diff", "HEAD", "--name-only", "--no-renames", "-z").split(b"\0") if p]
    filter_only = set()
    if tracked:
        lfs_paths = set()
        for extra in ([], ["--cached"]):
            attrs = subprocess.check_output(
                ["git", "-C", str(root), "check-attr", "-z", *extra, "--stdin", "filter"],
                input=b"".join(os.fsencode(p) + b"\0" for p in tracked), timeout=60)
            fields = attrs.split(b"\0")
            lfs_paths.update(os.fsdecode(fields[i]) for i in range(0, len(fields) - 2, 3)
                             if fields[i + 2] == b"lfs")
        heads = {}
        for entry in raw("ls-tree", "-r", "-z", "HEAD").split(b"\0"):
            if entry:
                meta, name = entry.split(b"\t", 1)
                mode, kind, oid = meta.split()
                heads[os.fsdecode(name)] = (mode, oid)
        indexes = {}
        for entry in raw("ls-files", "--stage", "-z").split(b"\0"):
            if entry:
                meta, name = entry.split(b"\t", 1)
                mode, oid, stage = meta.split()
                indexes.setdefault(os.fsdecode(name), []).append((mode, oid, stage))
        algorithm = raw("rev-parse", "--show-object-format").strip().decode()
        for name in lfs_paths:
            path = root / name
            head = heads.get(name)
            index = indexes.get(name, [])
            if (not path.is_file() or path.is_symlink() or head is None
                    or index != [(*head, b"0")]
                    or (head[0] == b"100755") != bool(path.stat().st_mode & 0o111)):
                raise RuntimeError("modified LFS files must be retained in place")
            h = hashlib.new(algorithm)
            h.update(f"blob {path.stat().st_size}\0".encode())
            with path.open("rb") as f:
                for chunk in iter(lambda: f.read(1024 * 1024), b""):
                    h.update(chunk)
            if h.hexdigest().encode() != head[1]:
                raise RuntimeError("modified LFS files must be retained in place")
            # New attributes can mark an unchanged historical blob as modified.
            filter_only.add(name)
    record["filter_only_paths"] = sorted(filter_only)
    exclude = ["--", ".", *(f":(literal,exclude){name}" for name in sorted(filter_only))]
    staged = raw("diff", "--cached", "--binary", "--no-ext-diff", "--no-textconv", *exclude)
    unstaged = raw("diff", "--binary", "--no-ext-diff", "--no-textconv", *exclude)
    untracked = [os.fsdecode(p) for p in raw("ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if p]
    names = set()
    def visit(p):
        if p.is_dir() and not p.is_symlink():
            if (p / ".git").exists():
                raise RuntimeError("nested Git repository must be retained in place")
            for child in p.iterdir():
                if child.name not in BUILD_DIRS:
                    visit(child)
        elif p.exists() or p.is_symlink():
            names.add(str(p.relative_to(root)))
    for name in [*untracked, *record["ignored"]]:
        if not BUILD_DIRS.intersection(Path(name).parts):
            visit(root / name)
    for name in set(tracked) - filter_only:
        visit(root / name)
    return staged, unstaged, sorted(names)


def archive_local(root, record, archive_dir):
    staged, unstaged, names = local_state(root, record)
    before = fingerprint(root, names)
    total = sum(v[1] for v in before.values())
    if total + 64 * 1024**3 > os.statvfs(archive_dir.parent).f_bavail * os.statvfs(archive_dir.parent).f_frsize:
        raise RuntimeError("insufficient headroom to archive local files safely")
    tag = hashlib.sha256((str(root) + record["head"] + json.dumps(before, sort_keys=True)).encode()
                         + staged + unstaged).hexdigest()[:24]
    recovery = archive_dir / f"recovery-{root.name}-{tag}"
    recovery.mkdir(mode=0o700, parents=True, exist_ok=True)
    for name, data in [("staged.patch", staged), ("unstaged.patch", unstaged)]:
        p = recovery / name
        p.write_bytes(data)
        p.chmod(0o600)
        with p.open("rb") as f:
            os.fsync(f.fileno())
    if names:
        proxy = dict(record, ignored=names)
        archive_ignored(root, proxy, recovery)
        record["archive"] = proxy["archive"]
    if ((staged, unstaged, names) != local_state(root, record)
            or before != fingerprint(root, names)):
        raise RuntimeError("local work changed while archiving; worktree kept")
    record["recovery"] = str(recovery)
    metadata = recovery / "metadata.json"
    metadata.write_text(json.dumps(dict(record, verified=True), indent=2) + "\n")
    metadata.chmod(0o600)
    with metadata.open("rb") as f:
        os.fsync(f.fileno())
    fd = os.open(recovery, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    return staged, unstaged, names, before


def retire(root, paths, idle_hours, dry_run=False, now=None, archive_dir=None,
           archive_local_changes=False, archive_unpublished=False):
    reason, record = inspect(root, paths, idle_hours, now, archive_local_changes, archive_unpublished)
    if reason != "eligible":
        return reason, record
    if record["ignored"] and archive_dir is None:
        return "ignored evidence or other data", None
    if not dry_run:
        if not record["published_ref"]:
            if archive_dir is None:
                return "unpublished commits", record
            archive_head(root, record, archive_dir)
        if record["dirty"]:
            if archive_dir is None:
                return "local changes", None
            saved = archive_local(root, record, archive_dir)
            reason, latest = inspect(root, active_paths(), idle_hours, now, True, archive_unpublished)
            if (reason != "eligible" or latest["head"] != record["head"]
                    or latest["dirty"] != record["dirty"]
                    or saved[:3] != local_state(root, latest)
                    or saved[3] != fingerprint(root, saved[2])):
                return "changed during archiving", record
        elif record["ignored"]:
            before = archive_ignored(root, record, archive_dir)
            reason, latest = inspect(root, active_paths(), idle_hours, now,
                                     allow_unpublished=archive_unpublished)
            if (reason != "eligible" or latest["head"] != record["head"]
                    or latest["ignored"] != record["ignored"]
                    or before != fingerprint(root, record["ignored"])):
                return "changed during archiving", record
        else:
            reason, latest = inspect(root, active_paths(), idle_hours, now,
                                     allow_unpublished=archive_unpublished)
            if reason != "eligible" or latest["head"] != record["head"]:
                return "changed during archiving", record
        subprocess.run(
            ["git", "--git-dir", record["common"], "worktree", "remove",
             *(["--force"] if record["dirty"] else []), "--", str(root)],
            check=True, capture_output=True, text=True, timeout=600,
            env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"),
        )
    return "would remove" if dry_run else "removed", record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--idle-hours", type=float, default=6)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--archive-dir", type=Path)
    parser.add_argument("--archive-local-changes", action="store_true",
                        help="one-off recovery: verify backups of local edits before retiring a published tree")
    parser.add_argument("--archive-unpublished", action="store_true",
                        help="one-off recovery: bundle unpublished commits and pin their base objects")
    parser.add_argument("--manifest", type=Path,
                        default=Path.home() / ".local/state/disk-watch/worktree-retirement.jsonl")
    parser.add_argument("roots", nargs="*", type=Path)
    args = parser.parse_args()
    if args.idle_hours < 1:
        parser.error("idle time must be at least one hour")
    if (args.archive_local_changes or args.archive_unpublished) and (args.idle_hours < 24 or args.archive_dir is None):
        parser.error("archiving local changes requires --idle-hours at least 24 and --archive-dir")
    args.manifest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with args.manifest.with_suffix(".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("another retirement pass is running", flush=True)
            return
        counts = Counter()
        paths, checked = active_paths(), time.monotonic()
        with args.manifest.open("a", buffering=1) as manifest:
            for root in args.roots or discover(Path.home()):
                if time.monotonic() - checked > 10:
                    paths, checked = active_paths(), time.monotonic()
                try:
                    reason, record = retire(root, paths, args.idle_hours, args.dry_run,
                                            archive_dir=args.archive_dir,
                                            archive_local_changes=args.archive_local_changes,
                                            archive_unpublished=args.archive_unpublished)
                except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                    reason, record = "could not verify or remove", None
                    print(f"kept {root}: {error}", flush=True)
                counts[reason] += 1
                if record is not None:
                    record.update(action=reason, timestamp=int(time.time()))
                    manifest.write(json.dumps(record) + "\n")
                if reason in ("removed", "would remove"):
                    print(f"{reason} {root}", flush=True)
                if sum(counts.values()) % 50 == 0:
                    print(f"progress: {dict(counts)}", flush=True)
            print(dict(counts), flush=True)


if __name__ == "__main__":
    main()
