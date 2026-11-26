"""Keep agent bulk writes and command output within the scratch image."""

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import selectors
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time


GIB = 1024**3
RECOVERY = {"agent-storage", "df", "du", "ls", "pwd", "stat", "rm", "rmdir", "unlink", "truncate"}
OUTPUT_HEADROOM = 256 * 1024**2


def agent_parent():
    pid = os.getppid()
    for _ in range(32):
        try:
            root = Path("/proc") / str(pid)
            name = (root / "comm").read_text().strip()
            if name in {"codex", "codex-code-mode", "claude", ".claude-unwrapp"}:
                return True
            status = (root / "status").read_text().splitlines()
            pid = int(next(line.split()[1] for line in status if line.startswith("PPid:")))
            if pid <= 1:
                break
        except (OSError, ValueError, StopIteration):
            break
    return False


def ready(bulk, output):
    if not os.path.ismount(bulk) or not os.path.ismount(output):
        raise RuntimeError("bounded storage is unavailable; start agent-storage.service")
    if bulk.stat().st_dev == output.stat().st_dev:
        raise RuntimeError("output reserve must be a separate filesystem inside scratch")


def recovery_command(argv):
    argv = argv[1:] if argv and argv[0] == "--" else argv
    if "-c" not in argv and "-lc" not in argv:
        return bool(argv) and Path(argv[0]).name in RECOVERY
    pos = argv.index("-c") if "-c" in argv else argv.index("-lc")
    try:
        words = shlex.split(argv[pos + 1])
    except (ValueError, IndexError):
        return False
    return bool(words) and Path(words[0]).name in RECOVERY


def admitted(argv, free, minimum):
    return free >= minimum or recovery_command(argv)


def process_start(pid):
    try:
        return (Path("/proc") / str(pid) / "stat").read_text().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return None


@contextmanager
def output_slot(output, limit):
    state = output / "state"
    jobs = state / "output-jobs"
    jobs.mkdir(mode=0o700, parents=True, exist_ok=True)
    lease = jobs / f"{os.getpid()}-{time.time_ns()}"
    with (state / "output-budget.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        active = 0
        for record in jobs.iterdir():
            try:
                data = json.loads(record.read_text())
                if process_start(data["pid"]) == data["start"]:
                    active += 1
                else:
                    record.unlink()
            except (OSError, ValueError, KeyError):
                continue
        if shutil.disk_usage(output).free < OUTPUT_HEADROOM + (active + 1) * (2 * limit + 512):
            request_cleanup()
            raise RuntimeError("output reserve is busy; new jobs are deferred so the agent can keep communicating")
        lease.write_text(json.dumps({"pid": os.getpid(), "start": process_start(os.getpid())}))
    try:
        yield
    finally:
        lease.unlink(missing_ok=True)


def relay(argv, env, limit):
    """Drain both pipes after the display limit so verbose jobs cannot block."""
    child = subprocess.Popen(argv, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    old_handlers = {}
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        old_handlers[signum] = signal.signal(signum, lambda sig, _frame: child.send_signal(sig)
                                            if child.poll() is None else None)
    selector = selectors.DefaultSelector()
    for source, destination in ((child.stdout, sys.stdout.buffer), (child.stderr, sys.stderr.buffer)):
        selector.register(source, selectors.EVENT_READ, [destination, 0, False])
    try:
        while selector.get_map():
            for key, _ in selector.select():
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                destination, written, truncated = key.data
                keep = data[:max(0, limit - written)]
                if keep:
                    destination.write(keep)
                    destination.flush()
                    key.data[1] += len(keep)
                if len(keep) < len(data) and not truncated:
                    destination.write(b"\n[agent-storage: output limit reached; remaining output drained. "
                                      b"Redirect large results to a file in scratch.]\n")
                    destination.flush()
                    key.data[2] = True
        result = child.wait()
        return result if result >= 0 else 128 - result
    finally:
        selector.close()
        for signum, previous in old_handlers.items():
            signal.signal(signum, previous)


def request_cleanup():
    try:
        result = subprocess.run(
            ["systemctl", "--user", "start", "--no-block", "agent-storage-cleanup.service"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def task_module(args):
    path = getattr(args, "task_helper", Path(__file__).with_name("agent-task-storage.py"))
    spec = importlib.util.spec_from_file_location("agent_task_storage", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reserve_task(args, tasks):
    amount = getattr(args, "command_reserve_gib", 0) * GIB
    if not amount:
        return tasks.create(args.bulk, args.output)
    state = args.output / "state"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (state / "bulk-budget.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        committed = tasks.reserved_bytes(args.bulk, args.output)
        if shutil.disk_usage(args.bulk).free < args.minimum_free_gib * GIB + committed + amount:
            return None
        return tasks.create(args.bulk, args.output, reservation_bytes=amount)


def command_namespace(args, argv, temporary, variable_temporary):
    return [args.bwrap, "--bind", "/", "/", "--dev-bind", "/dev", "/dev",
            "--bind", str(temporary), "/tmp",
            "--bind", str(variable_temporary), "/var/tmp",
            "--ro-bind", str(args.output), str(args.output),
            "--ro-bind", str(args.bulk / ".output-reserve"), str(args.bulk / ".output-reserve"),
            "--", *argv]


def command(args):
    ready(args.bulk, args.output)
    argv = args.argv
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        raise RuntimeError("a command is required")
    free = shutil.disk_usage(args.bulk).free
    if not admitted(argv, free, args.minimum_free_gib * GIB):
        request_cleanup()
        print(f"Scratch has {free / GIB:.1f} GiB free; new jobs need {args.minimum_free_gib} GiB. "
              "The agent is still running; use agent-storage status or cleanup. "
              "Run large builds with graphide-tools/utilities/scripts/remote.sh or fleet job.",
              file=sys.stderr)
        return 75
    env = dict(os.environ, TMPDIR=str(args.bulk / "tmp"),
               XDG_CACHE_HOME=str(args.bulk / "home/.cache"), AGENT_STORAGE_COMMAND="1")
    limit = args.output_limit_mib * 1024**2
    # Recovery must remain possible after normal output admission runs out.
    if recovery_command(args.argv):
        if env.get("AGENT_STORAGE_SESSION") == "1":
            argv = command_namespace(args, argv, args.bulk / "tmp", args.bulk / "var-tmp")
        return relay(argv, env, limit)
    with output_slot(args.output, limit):
        tasks = task_module(args)
        reserved = reserve_task(args, tasks)
        if reserved is None:
            request_cleanup()
            print("agent-storage: bulk space is already committed to running commands; "
                  "new work is deferred until their descendants finish.", file=sys.stderr)
            return 75
        task_id, path = reserved
        # Explicit /tmp paths are often handed between tool calls; only TMPDIR
        # is command-owned. Durable artifacts must live outside that directory.
        argv = command_namespace(args, argv, args.bulk / "tmp", args.bulk / "var-tmp")
        argv = tasks.launch_argv(task_id, args.bulk, args.output, argv, env)
        result = relay(argv, env, limit)
        return result


def session(args):
    ready(args.bulk, args.output)
    argv = args.argv[1:] if args.argv and args.argv[0] == "--" else args.argv
    if not argv:
        raise RuntimeError("an agent executable is required")
    env = dict(os.environ, TMPDIR=str(args.output / "tmp"), AGENT_STORAGE_SESSION="1",
               XDG_CACHE_HOME=str(args.bulk / "home/.cache"))
    env.pop("AGENT_STORAGE_COMMAND", None)
    argv = [args.bwrap, "--bind", "/", "/", "--dev-bind", "/dev", "/dev",
            "--bind", str(args.output / "tmp"), "/tmp",
            "--bind", str(args.output / "tmp"), "/var/tmp",
            "--bind", str(args.bulk / "home/.cache"), str(Path.home() / ".cache"),
            "--ro-bind", str(args.bulk / ".output-reserve"), str(args.bulk / ".output-reserve"),
            "--", *argv]
    os.execvpe(argv[0], argv, env)


def capacity(path):
    usage = shutil.disk_usage(path)
    stat = os.statvfs(path)
    return {"path": str(path), "total_gib": round(usage.total / GIB, 2),
            "used_gib": round(usage.used / GIB, 2), "free_gib": round(usage.free / GIB, 2),
            "free_bytes": usage.free,
            "free_inodes": stat.f_favail if stat.f_files else None,
            "total_inodes": stat.f_files or None}


def capacity_report(args, sample=False):
    result = {}
    for name, path in (("bulk", args.bulk), ("output", args.output), ("home", Path.home())):
        result[name] = capacity(path)
    # The existing cleanup timer supplies samples; no extra scanner or policy is needed.
    state = args.output / "state"
    sample_path = state / "capacity.json"
    current = {"boot": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
               "monotonic": time.monotonic(), "time": time.time(),
               "free": {key: item["free_bytes"] for key, item in result.items()}}
    @contextmanager
    def sample_lock():
        if not sample:
            yield
            return
        state.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (state / "capacity.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    with sample_lock():
        try:
            previous = json.loads(sample_path.read_text())
        except (OSError, ValueError):
            previous = {}
        elapsed = current["monotonic"] - previous.get("monotonic", current["monotonic"])
        for key, item in result.items():
            rate = None
            if previous.get("boot") == current["boot"] and elapsed > 0 and key in previous.get("free", {}):
                rate = (previous["free"][key] - item["free_bytes"]) / elapsed
            item["growth_bytes_per_second"] = round(rate, 2) if rate is not None else None
            item["sample_seconds"] = round(elapsed, 2) if rate is not None else None
            item["estimated_seconds_until_full"] = round(item["free_bytes"] / rate) if rate and rate > 0 else None
        if sample:
            fd, temporary = tempfile.mkstemp(prefix=".capacity-", dir=state)
            try:
                with os.fdopen(fd, "w") as stream:
                    json.dump(current, stream)
                os.replace(temporary, sample_path)
            finally:
                Path(temporary).unlink(missing_ok=True)
            history = state / "capacity-history.jsonl"
            if history.exists() and history.stat().st_size >= 1024**2:
                os.replace(history, history.with_suffix(".jsonl.1"))
            with history.open("a") as stream:
                stream.write(json.dumps(current) + "\n")
    return result


def status(args):
    ready(args.bulk, args.output)
    result = capacity_report(args)
    result["new_jobs_admitted"] = (
        shutil.disk_usage(args.bulk).free >= args.minimum_free_gib * GIB
        and shutil.disk_usage(args.output).free >= OUTPUT_HEADROOM + 2 * args.output_limit_mib * 1024**2 + 512
    )
    result["task_scratch"] = task_module(args).status(args.bulk, args.output)
    result["task_cleanup_enabled"] = getattr(args, "task_cleanup", False)
    result["runtime"] = {"path": str(Path(__file__).absolute()),
                         "sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    result["bulk_admission"] = {"command_reserve_gib": getattr(args, "command_reserve_gib", 0),
                                "reserved_bytes": task_module(args).reserved_bytes(args.bulk, args.output),
                                "filesystem_quota": False}
    result["bulk_admission"]["enabled"] = result["bulk_admission"]["command_reserve_gib"] > 0
    result["new_jobs_admitted"] = result["new_jobs_admitted"] and (not result["bulk_admission"]["enabled"] or (
        shutil.disk_usage(args.bulk).free >= args.minimum_free_gib * GIB
        + result["bulk_admission"]["reserved_bytes"]
        + result["bulk_admission"]["command_reserve_gib"] * GIB))
    result["session_history"] = "Retained in existing home/account locations; not subject to scratch cleanup."
    print(json.dumps(result))


def usage(args):
    ready(args.bulk, args.output)
    roots = {"all": args.bulk, "tasks": args.bulk / "tasks", "tmp": args.bulk / "tmp",
             "cache": args.bulk / "home/.cache"}
    print("Scanning the selected area on request; this can take time for large directory trees.",
          file=sys.stderr)
    return subprocess.run(["du", "--one-file-system", "--max-depth=1", "--block-size=1",
                           str(roots[args.area])]).returncode


def prune_go_cache(root, limit, open_files=(), now=None):
    """Evict only Go's reproducible hash entries, retaining open files."""
    now = time.time() if now is None else now
    if not root.is_dir() or root.is_symlink():
        return {"removed_bytes": 0, "remaining_bytes": 0}
    entries, total = [], 0
    for shard in root.iterdir():
        if not re.fullmatch(r"[0-9a-f]{2}", shard.name) or shard.is_symlink() or not shard.is_dir():
            continue
        for path in shard.iterdir():
            if not re.fullmatch(r"[0-9a-f]{64}-[ad]", path.name):
                continue
            try:
                info = path.lstat()
                if stat.S_ISREG(info.st_mode):
                    size = info.st_blocks * 512
                    total += size
                    entries.append((info.st_mtime, path, size, (info.st_dev, info.st_ino)))
            except FileNotFoundError:
                pass
    removed = 0
    for modified, path, size, identity in sorted(entries):
        if total <= limit:
            break
        # noatime mounts cannot provide a last-read signal. Cache entries are
        # rebuildable; use a write-age grace period, not a claim of inactivity.
        if now - modified < 3600 or str(path) in open_files or identity in open_files:
            continue
        try:
            path.unlink()
            removed += size
            total -= size
        except FileNotFoundError:
            pass
    return {"removed_bytes": removed, "remaining_bytes": total}


def prune_build_caches(args, open_files, now):
    if not getattr(args, "cache_cleanup", False) or shutil.disk_usage(args.bulk).free >= args.cleanup_free_gib * GIB:
        return {}
    cache = args.bulk / "home/.cache"
    result = {"go": prune_go_cache(cache / "go-build", 2 * GIB, open_files, now)}
    uv = getattr(args, "uv", None)
    if uv and (cache / "uv").is_dir() and not (cache / "uv").is_symlink():
        try:
            done = subprocess.run([uv, "cache", "prune", "--cache-dir", str(cache / "uv")],
                                  env=dict(os.environ, UV_LOCK_TIMEOUT="0"),
                                  capture_output=True, text=True, timeout=30)
            result["uv"] = {"returncode": done.returncode}
            if done.returncode:
                result["uv"]["state"] = "busy" if "Cache is currently in-use" in done.stderr else "failed"
                if result["uv"]["state"] == "failed":
                    result["uv"]["error"] = done.stderr[-500:]
        except (OSError, subprocess.SubprocessError) as error:
            result["uv"] = {"error": str(error)}
    return result


def cleanup(args):
    """Reclaim verified disposable data, retaining unowned and active work."""
    ready(args.bulk, args.output)
    if os.environ.get("AGENT_STORAGE_COMMAND") == "1" and not os.access(args.output, os.W_OK):
        requested = request_cleanup()
        print(json.dumps({"cleanup_requested_outside_command_namespace": requested}))
        if not requested:
            raise RuntimeError("cleanup service unavailable; run agent-storage cleanup from a host terminal")
        return
    open_files = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    open_files.add(os.readlink(fd))
                    info = fd.stat()
                    open_files.add((info.st_dev, info.st_ino))
                except OSError:
                    pass
        except OSError:
            pass
    now = time.time()
    before = shutil.disk_usage(args.bulk).free
    removed = 0
    output_age = 300 if shutil.disk_usage(args.output).free < 2 * GIB else 86400
    cache_roots = [args.bulk / "tmp/ghc/cache", args.bulk / "home/.cache/tmp-overflow/ghc-response-cache"]
    candidates = [path for root in cache_roots for path in root.glob("*.json")]
    partials = set()
    for root in cache_roots:
        for path in root.glob("*.json.*"):
            match = re.fullmatch(r"[0-9a-f]{64}\.json\.([1-9][0-9]*)", path.name)
            if match and not (Path("/proc") / match[1]).exists():
                partials.add(path)
                candidates.append(path)
    candidates += list((args.output / "tmp").glob("claude-*/**/*.output"))
    legacy = getattr(args, "legacy_tmp", None)
    legacy_age = 86400
    if legacy is not None and legacy.stat().st_dev != args.bulk.stat().st_dev:
        legacy_age = 60 if shutil.disk_usage(legacy).free < 2 * GIB else 86400
        candidates += list((legacy / f"claude-{os.getuid()}").glob("**/*.output"))
    for path in candidates:
        try:
            minimum_age = 3600 if path in partials else (
                output_age if path.is_relative_to(args.output) else (
                    legacy_age if legacy is not None and path.is_relative_to(legacy) else 86400))
            info = path.stat()
            if (not path.is_symlink() and path.is_file() and str(path) not in open_files
                    and (info.st_dev, info.st_ino) not in open_files
                    and str(path.resolve()) not in open_files
                    and now - max(path.stat().st_mtime, path.stat().st_ctime) > minimum_age):
                path.unlink()
                removed += 1
        except FileNotFoundError:
            pass
    print(json.dumps({"removed_expired_cache_or_closed_output_files": removed}))
    print(json.dumps({"task_scratch": task_module(args).cleanup(
        args.bulk, args.output, apply=getattr(args, "task_cleanup", False))}))
    print(json.dumps({"build_caches": prune_build_caches(args, open_files, now)}))
    after = shutil.disk_usage(args.bulk).free
    print(json.dumps({"bulk_free_bytes": after, "net_free_change_bytes": after - before}))
    alert = args.output / "state/pressure-alert"
    if after < 24 * GIB and (not alert.exists() or now - alert.stat().st_mtime > 900):
        notifier = shutil.which("notify-send")
        if notifier:
            try:
                done = subprocess.run([notifier, "-a", "agent-storage", "Scratch storage pressure",
                                       f"{after / GIB:.1f} GiB free. Retained work or running commands may prevent cleanup; check agent-storage status."],
                                      capture_output=True, timeout=5)
                if done.returncode == 0:
                    alert.parent.mkdir(parents=True, exist_ok=True)
                    alert.touch()
            except (OSError, subprocess.SubprocessError):
                pass
    # Workspace scans have independent timers; retrying them every minute under
    # pressure creates sustained I/O contention without changing eligibility.
    try:
        capacity_report(args, sample=True)
    except OSError as error:
        print(f"agent-storage: capacity sample unavailable: {error}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bulk", type=Path, default=Path("/var/lib/agent-scratch"))
    parser.add_argument("--output", type=Path, default=Path("/var/lib/agent-output"))
    parser.add_argument("--legacy-tmp", type=Path, default=Path("/tmp"))
    parser.add_argument("--bwrap", default="bwrap")
    parser.add_argument("--minimum-free-gib", type=int, default=8)
    parser.add_argument("--cleanup-free-gib", type=int, default=32)
    parser.add_argument("--output-limit-mib", type=int, default=8)
    parser.add_argument("--command-reserve-gib", type=int, default=0)
    parser.add_argument("--uv")
    parser.add_argument("--cache-cleanup", action="store_true")
    parser.add_argument("--task-helper", type=Path, default=Path(__file__).with_name("agent-task-storage.py"))
    parser.add_argument("--task-cleanup", action="store_true",
                        help="reclaim launcher-owned scratch only after its tracked process tree exits")
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("session", "command"):
        child = sub.add_parser(name)
        child.add_argument("argv", nargs=argparse.REMAINDER)
    for name in ("status", "cleanup", "is-agent"):
        sub.add_parser(name)
    child = sub.add_parser("usage", help="explicitly scan one area to identify large directories")
    child.add_argument("--area", choices=("all", "tasks", "tmp", "cache"), default="all")
    args = parser.parse_args()
    if args.command_reserve_gib < 0:
        parser.error("command reserve must be nonnegative")
    if args.action == "is-agent":
        return 0 if agent_parent() else 1
    if args.action == "session":
        session(args)
    if args.action == "command":
        return command(args)
    if args.action == "status":
        status(args)
    if args.action == "cleanup":
        cleanup(args)
    if args.action == "usage":
        return usage(args)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"agent-storage: {error}", file=sys.stderr)
        sys.exit(75)
