"""Task scratch whose lifetime includes every descendant of its command.

A detached Linux subreaper supervises each task. It returns the command's
status immediately but certifies completion only after all descendants exit.
The caller decides whether to apply cleanup; cleanup never signals processes.
TMPDIR is ephemeral; persistent artifacts and worktrees belong elsewhere.
Work submitted to an external service manager needs its own scratch lifetime.
Commands with a controlling terminal execute directly and retain their scratch.
"""

import argparse
from contextlib import contextmanager
import ctypes
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import stat
import subprocess
import sys
import uuid


def _id(value):
    parsed = uuid.UUID(value)
    if str(parsed) != value or parsed.version != 4:
        raise ValueError("invalid task UUID")
    return value


def _directory(path, create=False):
    """Walk with descriptors so symlinked ancestors are refused."""
    path = Path(os.path.abspath(path))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


@contextmanager
def _registry(output, create=False):
    fd = _directory(Path(output) / "state/task-jobs", create)
    try:
        yield fd
    finally:
        os.close(fd)


@contextmanager
def _lock(registry, task_id, readonly=False, create=False):
    flags = os.O_RDONLY if readonly else os.O_RDWR
    if create:
        flags |= os.O_CREAT
    fd = os.open(task_id + ".lock", flags | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=registry)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError("invalid task lock")
        fcntl.flock(fd, fcntl.LOCK_SH if readonly else fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def _read(registry, task_id):
    fd = os.open(task_id + ".json", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=registry)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > 16384:
            raise ValueError("invalid task record")
        return json.load(stream)


def _write(registry, task_id, record):
    temporary = task_id + "." + str(uuid.uuid4()) + ".new"
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                 0o600, dir_fd=registry)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(record, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.rename(temporary, task_id + ".json", src_dir_fd=registry, dst_dir_fd=registry)
        os.fsync(registry)
    finally:
        try:
            os.unlink(temporary, dir_fd=registry)
        except FileNotFoundError:
            pass


def _task_path(bulk, task_id):
    return Path(os.path.abspath(bulk)) / "tasks" / _id(task_id)


def _validate(record, bulk, task_id):
    path = _task_path(bulk, task_id)
    if (not isinstance(record, dict) or record.get("schema") != 2
            or record.get("id") != task_id or record.get("task_path") != str(path)
            or any(type(record.get(key)) is not bool for key in ("tracked", "started", "completed"))
            or any(type(record.get(key)) is not int for key in ("device", "inode"))):
        raise ValueError("invalid task record")
    if record["tracked"] and (not record["started"] or type(record.get("supervisor_pid")) is not int
            or record["supervisor_pid"] <= 0 or not isinstance(record.get("supervisor_start"), str)
            or not record["supervisor_start"].isdigit()
            or not isinstance(record.get("boot_id"), str)):
        raise ValueError("invalid task supervisor")
    return path


def create(bulk, output, reservation_bytes=0):
    if type(reservation_bytes) is not int or reservation_bytes < 0:
        raise ValueError("invalid bulk reservation")
    task_id = str(uuid.uuid4())
    path = _task_path(bulk, task_id)
    with _registry(output, create=True) as registry, _lock(registry, task_id, create=True):
        tasks = _directory(path.parent, create=True)
        try:
            os.mkdir(task_id, mode=0o700, dir_fd=tasks)
            task = os.open(task_id, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=tasks)
            try:
                for name in ("tmp", "var-tmp"):
                    os.mkdir(name, mode=0o700, dir_fd=task)
                info = os.fstat(task)
            finally:
                os.close(task)
            _write(registry, task_id, {"schema": 2, "id": task_id, "task_path": str(path),
                   "tracked": False, "started": False, "completed": False,
                   "device": info.st_dev, "inode": info.st_ino,
                   "created_boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                   "reservation_bytes": reservation_bytes})
        finally:
            os.close(tasks)
    return task_id, path


def reserved_bytes(bulk, output):
    """Count commitments until the descendant supervisor certifies completion."""
    total = 0
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    try:
        with _registry(output) as registry:
            for name in os.listdir(registry):
                if not name.endswith(".json"):
                    continue
                task_id = _id(name[:-5])
                try:
                    with _lock(registry, task_id, readonly=True):
                        record = _read(registry, task_id)
                        amount = record.get("reservation_bytes", 0)
                        if type(amount) is not int or amount < 0:
                            raise ValueError("invalid bulk reservation")
                        if amount:
                            _validate(record, bulk, task_id)
                            # A reboot proves old descendants are gone. Keep
                            # uncertain task data without holding admission forever.
                            same_boot = record.get("boot_id", record.get("created_boot_id", boot)) == boot
                            if not record["completed"] and same_boot:
                                total += amount
                except FileNotFoundError:
                    continue
    except FileNotFoundError:
        # The registry does not exist before the first task. Removal races can
        # only release completed reservations; the caller holds the budget lock.
        pass
    return total


def _subreaper():
    try:
        return ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) == 0
    except (OSError, AttributeError):
        return False


def _identity():
    start = Path("/proc/self/stat").read_text().rsplit(")", 1)[1].split()[19]
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    return {"supervisor_pid": os.getpid(), "supervisor_start": start, "boot_id": boot}


def launch_argv(task_id, bulk, output, argv, env=None, *, systemd_available=True):
    """Return launcher argv; the caller passes env to its subprocess as usual.

    systemd_available remains accepted for compatibility. Subreaper ownership
    works without a user bus and survives descendants moving between cgroups.
    """
    path = _task_path(bulk, task_id)
    if not argv:
        raise ValueError("a command is required")
    if env is not None:
        env.update(TMPDIR=str(path / "tmp"), AGENT_TASK_ID=task_id, AGENT_TASK_DIR=str(path))
    return [sys.executable, str(Path(__file__).absolute()), "launch", "--id", task_id,
            "--bulk", str(Path(bulk).absolute()), "--output", str(Path(output).absolute()),
            "--", *map(str, argv)]


@contextmanager
def _forward_signals(handler):
    previous = {}
    try:
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            previous[signum] = signal.signal(signum, handler)
        yield
    finally:
        for signum, original in previous.items():
            signal.signal(signum, original)


def _worker(args):
    state = {"child": None, "pending": []}

    def forward(signum, _frame):
        child = state["child"]
        if child is None:
            state["pending"].append(signum)
        elif child.poll() is None:
            try:
                os.killpg(child.pid, signum)
            except ProcessLookupError:
                pass

    state["forward"] = forward
    with _forward_signals(forward):
        return _supervise(args, state)


def _supervise(args, state):
    result = socket.socket(fileno=args.result_fd)
    tracked = _subreaper()
    identity = _identity()
    with _registry(args.output) as registry, _lock(registry, args.id):
        record = _read(registry, args.id)
        path = _validate(record, args.bulk, args.id)
        if record["started"]:
            raise RuntimeError("task command already started")
        task = _directory(path)
        try:
            info = os.fstat(task)
            if (info.st_dev, info.st_ino) != (record["device"], record["inode"]):
                raise ValueError("task directory was replaced")
        finally:
            os.close(task)
        record.update(started=True, tracked=tracked, **identity)
        _write(registry, args.id, record)
    env = dict(os.environ, TMPDIR=str(path / "tmp"), AGENT_TASK_ID=args.id, AGENT_TASK_DIR=str(path))
    try:
        child = subprocess.Popen(args.argv, env=env, close_fds=True, start_new_session=True)
        state["child"] = child
        for signum in state["pending"]:
            state["forward"](signum, None)
        state["pending"].clear()
        code = child.wait()
        code = code if code >= 0 else 128 - code
    except OSError as error:
        print("agent-task-storage: " + str(error), file=sys.stderr)
        code = 127
    try:
        result.sendall(str(code).encode() + b"\n")
    except OSError:
        pass
    finally:
        result.close()
    # A redirected background child must not keep the caller's output pipes open
    # just because its supervisor still exists.
    for fd in (0, 1, 2):
        try:
            os.close(fd)
        except OSError:
            pass
    if tracked:
        while True:
            try:
                os.waitpid(-1, 0)
            except InterruptedError:
                continue
            except ChildProcessError:
                break
        with _registry(args.output) as registry, _lock(registry, args.id):
            record = _read(registry, args.id)
            _validate(record, args.bulk, args.id)
            if any(record.get(key) != value for key, value in identity.items()):
                raise ValueError("task supervisor changed")
            record["completed"] = True
            _write(registry, args.id, record)
    return 0


def _controlling_tty():
    if not os.isatty(0):
        return False
    try:
        fd = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY | os.O_CLOEXEC)
    except OSError:
        return False
    os.close(fd)
    return True


def _interactive_exec(args):
    # Detaching a supervisor loses the controlling terminal. Preserve the
    # caller's terminal semantics and retain scratch without a completion claim.
    with _registry(args.output) as registry, _lock(registry, args.id):
        record = _read(registry, args.id)
        path = _validate(record, args.bulk, args.id)
        if record["started"]:
            raise RuntimeError("task command already started")
        task = _directory(path)
        try:
            info = os.fstat(task)
            if (info.st_dev, info.st_ino) != (record["device"], record["inode"]):
                raise ValueError("task directory was replaced")
        finally:
            os.close(task)
        record.update(started=True, tracked=False, completed=False, reason="interactive-tty",
                      reservation_bytes=0)
        _write(registry, args.id, record)
    env = dict(os.environ, TMPDIR=str(path / "tmp"), AGENT_TASK_ID=args.id, AGENT_TASK_DIR=str(path))
    os.execvpe(args.argv[0], args.argv, env)


def _launch(args):
    if _controlling_tty():
        return _interactive_exec(args)
    receiver, sender = socket.socketpair()
    worker = None
    pending = []

    def forward(signum, _frame):
        if worker is None:
            pending.append(signum)
        else:
            worker.send_signal(signum)

    try:
        argv = [sys.executable, str(Path(__file__).absolute()), "worker", "--id", args.id,
                "--bulk", str(args.bulk), "--output", str(args.output),
                "--result-fd", str(sender.fileno()), "--", *args.argv]
        with _forward_signals(forward):
            # The worker outlives this launcher when a redirected descendant survives.
            worker = subprocess.Popen(argv, pass_fds=(sender.fileno(),), start_new_session=True)
            for signum in pending:
                worker.send_signal(signum)
            pending.clear()
            sender.close()
            data = b""
            while not data.endswith(b"\n") and len(data) < 32:
                block = receiver.recv(32)
                if not block:
                    break
                data += block
            if data.endswith(b"\n"):
                return int(data)
            code = worker.wait()
            return (128 - code if code < 0 else code) or 1
    finally:
        sender.close()
        receiver.close()


def _inspect(bulk, output, apply):
    summary = {"tasks": 0, "eligible": 0, "removed": 0, "retained": 0, "reasons": {}}
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    try:
        tasks = _directory(Path(bulk) / "tasks")
    except FileNotFoundError:
        return summary
    except OSError:
        summary["reasons"]["unsafe-task-root"] = 1
        return summary
    try:
        for name in os.listdir(tasks):
            summary["tasks"] += 1
            reason = "unknown"
            removed = False
            try:
                _id(name)
                with _registry(output) as registry, _lock(registry, name, readonly=not apply):
                    record = _read(registry, name)
                    _validate(record, bulk, name)
                    task = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=tasks)
                    try:
                        info = os.fstat(task)
                        if (info.st_dev, info.st_ino) != (record["device"], record["inode"]):
                            raise ValueError("task directory was replaced")
                    finally:
                        os.close(task)
                    reason = ("completed" if record["completed"] else "active-or-incomplete") \
                        if record["tracked"] else "untracked"
                    if record["tracked"] and not record["completed"]:
                        try:
                            previous = str(uuid.UUID(record["boot_id"]))
                            if previous == record["boot_id"] and previous != boot:
                                reason = "previous-boot"
                        except ValueError:
                            pass
                    if not record["tracked"] and record.get("reason") == "interactive-tty":
                        reason = "interactive-tty"
                    if reason in {"completed", "previous-boot"}:
                        summary["eligible"] += 1
                        if apply:
                            shutil.rmtree(name, dir_fd=tasks)
                            os.unlink(name + ".json", dir_fd=registry)
                            # UUID task names are never reused, and readers only open
                            # existing locks, so no late observer recreates this lock.
                            os.unlink(name + ".lock", dir_fd=registry)
                            summary["removed"] += 1
                            removed = True
            except (OSError, ValueError, TypeError, AttributeError):
                reason = "unknown"
            if not removed:
                summary["retained"] += 1
            summary["reasons"][reason] = summary["reasons"].get(reason, 0) + 1
    finally:
        os.close(tasks)
    return summary


def cleanup(bulk, output, apply=False):
    return _inspect(bulk, output, apply)


def status(bulk, output):
    """Read task counts without traversing scratch data or changing metadata."""
    return _inspect(bulk, output, False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("launch", "worker"))
    parser.add_argument("--id", required=True, type=_id)
    parser.add_argument("--bulk", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--result-fd", type=int)
    args, argv = parser.parse_known_args()
    args.argv = argv[1:] if argv[:1] == ["--"] else argv
    if not args.argv or args.action == "worker" and args.result_fd is None:
        parser.error("a command and worker result descriptor are required")
    try:
        return _launch(args) if args.action == "launch" else _worker(args)
    except (OSError, ValueError, RuntimeError) as error:
        # The supervisor can discover a late reserve error after closing stderr.
        try:
            print("agent-task-storage: " + str(error), file=sys.stderr)
        except OSError:
            pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
