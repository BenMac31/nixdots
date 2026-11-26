import importlib.util
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import pty
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid
from unittest.mock import patch


HELPER = Path(__file__).parents[1] / "modules/home-manager/term/agent-task-storage.py"
spec = importlib.util.spec_from_file_location("task_storage", HELPER)
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class Tasks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.bulk = Path(self.temporary.name) / "bulk"
        self.output = Path(self.temporary.name) / "output"

    def record_path(self, task_id):
        return self.output / "state/task-jobs" / (task_id + ".json")

    def read(self, task_id):
        return json.loads(self.record_path(task_id).read_text())

    def write(self, task_id, **fields):
        record = self.read(task_id)
        record.update(fields)
        self.record_path(task_id).write_text(json.dumps(record))

    def wait_for(self, condition):
        deadline = time.monotonic() + 10
        while not condition() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(condition())

    def completed(self):
        task_id, path = storage.create(self.bulk, self.output)
        self.write(task_id, tracked=True, started=True, completed=True,
                   supervisor_pid=123, supervisor_start="1", boot_id="test-boot")
        return task_id, path

    def test_reboot_proves_tracked_descendants_are_gone_but_untracked_data_is_retained(self):
        task_id, path = self.completed()
        self.write(task_id, completed=False, boot_id=str(uuid.uuid4()))
        other, retained = storage.create(self.bulk, self.output)
        self.write(other, boot_id=str(uuid.uuid4()))
        preview = storage.status(self.bulk, self.output)
        self.assertEqual(preview["reasons"], {"previous-boot": 1, "untracked": 1})
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 1)
        self.assertFalse(path.exists())
        self.assertTrue(retained.exists())

    def execute(self, task_id, code, systemd_available=True):
        env = dict(os.environ, AGENT_STORAGE_COMMAND="1")
        argv = storage.launch_argv(task_id, self.bulk, self.output,
                                  [sys.executable, "-c", code], env,
                                  systemd_available=systemd_available)
        return subprocess.run(argv, env=env, capture_output=True, text=True, timeout=10)

    def test_private_layout_unknown_untracked_and_legacy_are_retained(self):
        task_id, path = storage.create(self.bulk, self.output)
        self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        self.assertEqual(sorted(p.name for p in path.iterdir()), ["tmp", "var-tmp"])
        (self.bulk / "tasks/unknown").mkdir()
        source = self.bulk / "tmp/source"
        source.parent.mkdir()
        source.write_text("keep")
        summary = storage.cleanup(self.bulk, self.output, True)
        self.assertEqual(summary["removed"], 0)
        self.assertEqual(summary["reasons"], {"untracked": 1, "unknown": 1})
        self.assertTrue(source.exists())
        self.assertTrue(path.exists())

    def test_reboot_releases_admission_without_deleting_uncertain_task_data(self):
        task_id, path = storage.create(self.bulk, self.output, reservation_bytes=1024)
        self.assertEqual(storage.reserved_bytes(self.bulk, self.output), 1024)
        self.write(task_id, created_boot_id="previous-boot")
        self.assertEqual(storage.reserved_bytes(self.bulk, self.output), 0)
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 0)
        self.assertTrue(path.exists())

    def test_preview_then_delete_completed_task_only(self):
        task_id, path = self.completed()
        (path / "tmp/artifact").write_text("disposable")
        self.assertEqual(storage.cleanup(self.bulk, self.output)["eligible"], 1)
        self.assertTrue(path.exists())
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 1)
        self.assertFalse(path.exists())
        self.assertFalse(self.record_path(task_id).exists())
        self.assertFalse(self.record_path(task_id).with_suffix(".lock").exists())

    def test_concurrent_cleaners_leave_no_completed_task_locks(self):
        for _ in range(8):
            self.completed()
        unrelated = self.bulk / "tasks/source"
        unrelated.mkdir()
        (unrelated / "code").write_text("keep")
        start = threading.Barrier(5)

        def clean():
            start.wait()
            return storage.cleanup(self.bulk, self.output, True)

        with ThreadPoolExecutor(max_workers=4) as executor:
            results = [executor.submit(clean) for _ in range(4)]
            start.wait()
            summaries = [result.result(timeout=10) for result in results]
        self.assertEqual(sum(result["removed"] for result in summaries), 8)
        self.assertEqual(list((self.output / "state/task-jobs").iterdir()), [])
        self.assertEqual((unrelated / "code").read_text(), "keep")

    def test_incomplete_supervisor_and_untracked_completed_records_are_retained(self):
        task_id, path = self.completed()
        self.write(task_id, completed=False)
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["reasons"], {"active-or-incomplete": 1})
        self.write(task_id, completed=True, tracked=False)
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["reasons"], {"untracked": 1})
        self.assertTrue(path.exists())

    def test_malformed_metadata_and_path_traversal_are_retained(self):
        for change in ({"task_path": "/"}, {"task_path": str(self.bulk / "tasks/../source")},
                       {"tracked": "yes"}, {"schema": 1}, {"completed": "yes"},
                       {"supervisor_pid": -1}, {"supervisor_start": None}):
            with self.subTest(change=change):
                task_id, path = self.completed()
                self.write(task_id, **change)
                storage.cleanup(self.bulk, self.output, True)
                self.assertTrue(path.exists())
        task_id, path = storage.create(self.bulk, self.output)
        self.record_path(task_id).write_text("{broken")
        storage.cleanup(self.bulk, self.output, True)
        self.assertTrue(path.exists())

    def test_task_record_lock_and_root_symlinks_are_refused(self):
        for kind in ("task", "record", "lock"):
            with self.subTest(kind=kind):
                task_id, path = self.completed()
                target = self.bulk / ("safe-" + task_id)
                target.mkdir()
                (target / "source").write_text("keep")
                if kind == "task":
                    shutil.rmtree(path)
                    path.symlink_to(target, target_is_directory=True)
                elif kind == "record":
                    self.record_path(task_id).unlink()
                    self.record_path(task_id).symlink_to(target / "source")
                else:
                    lock = self.record_path(task_id).with_suffix(".lock")
                    lock.unlink()
                    lock.symlink_to(target / "source")
                storage.cleanup(self.bulk, self.output, True)
                self.assertTrue(path.exists())
                self.assertEqual((target / "source").read_text(), "keep")
        original = self.bulk / "tasks"
        original.rename(self.bulk / "original")
        original.symlink_to(self.bulk / "original", target_is_directory=True)
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["reasons"], {"unsafe-task-root": 1})

    def test_replaced_task_directory_is_retained(self):
        task_id, path = self.completed()
        path.rename(path.with_name("original"))
        path.mkdir()
        storage.cleanup(self.bulk, self.output, True)
        self.assertTrue(path.exists())

    def test_fifo_records_and_locks_are_refused_without_blocking(self):
        for suffix in (".json", ".lock"):
            task_id, path = self.completed()
            malformed = self.record_path(task_id).with_suffix(suffix)
            malformed.unlink()
            os.mkfifo(malformed)
            self.assertEqual(storage.status(self.bulk, self.output)["eligible"], 0)
            self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 0)
            self.assertTrue(path.exists())

    def test_status_and_preview_are_readonly_and_do_not_walk_task_contents(self):
        self.completed()
        real_open = storage.os.open

        def readonly(path, flags, *args, **kwargs):
            self.assertFalse(flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT), str(path))
            return real_open(path, flags, *args, **kwargs)

        with patch.object(storage.os, "open", side_effect=readonly), \
                patch.object(storage.shutil, "rmtree", side_effect=AssertionError("must not delete")), \
                patch.object(storage.shutil, "disk_usage", side_effect=AssertionError("must not size")):
            self.assertEqual(storage.status(self.bulk, self.output)["eligible"], 1)
            self.assertEqual(storage.cleanup(self.bulk, self.output)["eligible"], 1)

    def test_exit42_and_environment_preserved_without_rerunning_command(self):
        task_id, path = storage.create(self.bulk, self.output)
        result = self.execute(task_id,
            "import os; from pathlib import Path; assert os.environ['AGENT_STORAGE_COMMAND']=='1'; "
            "Path(os.environ['TMPDIR'],'calls').open('a').write('once\\n'); raise SystemExit(42)",
            systemd_available=False)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual((path / "tmp/calls").read_text(), "once\n")
        self.wait_for(lambda: self.read(task_id)["completed"])
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 1)

    def test_controlling_pty_exec_preserves_dev_tty_and_exit42_and_retains_scratch(self):
        task_id, path = storage.create(self.bulk, self.output)
        env = dict(os.environ)
        code = ("import os; from pathlib import Path; "
                "assert os.isatty(0); assert os.tcgetpgrp(0)==os.getpgrp(); "
                "f=os.open('/dev/tty',os.O_RDWR); os.write(f,b'tty works\\n'); os.close(f); "
                "Path(os.environ['TMPDIR'],'tty-opened').write_text('yes'); raise SystemExit(42)")
        argv = storage.launch_argv(task_id, self.bulk, self.output, [sys.executable, "-c", code], env)
        child, master = pty.fork()
        if child == 0:
            try:
                os.execvpe(argv[0], argv, env)
            except BaseException:
                os._exit(127)
        try:
            _, status = os.waitpid(child, 0)
        finally:
            os.close(master)
        self.assertEqual(os.waitstatus_to_exitcode(status), 42)
        self.assertEqual((path / "tmp/tty-opened").read_text(), "yes")
        record = self.read(task_id)
        self.assertTrue(record["started"])
        self.assertFalse(record["tracked"])
        self.assertFalse(record["completed"])
        self.assertEqual(storage.status(self.bulk, self.output)["reasons"], {"interactive-tty": 1})
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 0)
        self.assertTrue(path.exists())

    def background(self, reservation_bytes=0):
        task_id, path = storage.create(self.bulk, self.output, reservation_bytes=reservation_bytes)
        release = path / "tmp/release"
        os.mkfifo(release)
        # setsid and two forks exercise adoption beyond the direct child's PID.
        code = ("import os; from pathlib import Path\n"
                "p=Path(os.environ['TMPDIR'])\n"
                "if os.fork()==0:\n"
                " os.setsid()\n"
                " if os.fork(): os._exit(0)\n"
                " f=os.open('/dev/null',os.O_RDWR)\n"
                " for target in (0,1,2): os.dup2(f,target)\n"
                " (p/'ready').write_text(str(os.getpid()))\n"
                " f=os.open(p/'release',os.O_RDONLY); os.read(f,1); os.close(f); os._exit(0)\n"
                "os.waitpid(-1,0)\n")
        result = self.execute(task_id, code)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.wait_for(lambda: (path / "tmp/ready").exists())
        return task_id, path, release

    def test_redirected_setsid_doublefork_child_retains_task_after_leader_returns(self):
        task_id, path, release = self.background(reservation_bytes=123456)
        try:
            self.assertFalse(self.read(task_id)["completed"])
            self.assertEqual(storage.reserved_bytes(self.bulk, self.output), 123456)
            self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 0)
            self.assertTrue(path.exists())
        finally:
            with release.open("w") as stream:
                stream.write("x")
        self.wait_for(lambda: self.read(task_id)["completed"])
        self.assertEqual(storage.reserved_bytes(self.bulk, self.output), 0)
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 1)
        self.assertFalse(path.exists())

    def test_killed_supervisor_never_certifies_completion(self):
        task_id, path, release = self.background()
        supervisor = self.read(task_id)["supervisor_pid"]
        # This is the disposable supervisor started by this test, never an agent.
        os.kill(supervisor, signal.SIGKILL)
        with release.open("w") as stream:
            stream.write("x")
        self.assertFalse(self.read(task_id)["completed"])
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 0)
        self.assertTrue(path.exists())

    def test_launcher_sigterm_reaches_command_and_surviving_child_stays_owned(self):
        task_id, path = storage.create(self.bulk, self.output)
        release = path / "tmp/release"
        os.mkfifo(release)
        code = ("import os,signal; from pathlib import Path\n"
                "p=Path(os.environ['TMPDIR'])\n"
                "def terminate(signum,frame):\n"
                " (p/'received-term').write_text('yes'); raise SystemExit(143)\n"
                "signal.signal(signal.SIGTERM,terminate)\n"
                "if os.fork()==0:\n"
                " os.setsid()\n"
                " signal.signal(signal.SIGTERM,signal.SIG_DFL)\n"
                " f=os.open('/dev/null',os.O_RDWR)\n"
                " for target in (0,1,2): os.dup2(f,target)\n"
                " (p/'background-ready').write_text(str(os.getpid()))\n"
                " f=os.open(p/'release',os.O_RDONLY); os.read(f,1); os.close(f); os._exit(0)\n"
                "(p/'command-ready').write_text(str(os.getpid()))\n"
                "while True: signal.pause()\n")
        env = dict(os.environ)
        argv = storage.launch_argv(task_id, self.bulk, self.output, [sys.executable, "-c", code], env)
        launcher = subprocess.Popen(argv, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.wait_for(lambda: (path / "tmp/command-ready").exists()
                          and (path / "tmp/background-ready").exists())
            command_pid = int((path / "tmp/command-ready").read_text())
            launcher.send_signal(signal.SIGTERM)
            stdout, stderr = launcher.communicate(timeout=10)
            self.assertEqual(launcher.returncode, 143, stderr.decode())
            self.assertEqual((path / "tmp/received-term").read_text(), "yes")
            self.assertFalse(Path(f"/proc/{command_pid}").exists())
            self.assertFalse(self.read(task_id)["completed"])
            self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 0)
            self.assertTrue(path.exists())
        finally:
            if launcher.poll() is None:
                launcher.send_signal(signal.SIGTERM)
                launcher.communicate(timeout=10)
            if (path / "tmp/background-ready").exists():
                with release.open("w") as stream:
                    stream.write("x")
        self.wait_for(lambda: self.read(task_id)["completed"])
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 1)

    def test_forwarding_handlers_are_restored(self):
        signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
        previous = {signum: signal.getsignal(signum) for signum in signals}
        handler = lambda _signum, _frame: None
        with self.assertRaisesRegex(RuntimeError, "fixture"):
            with storage._forward_signals(handler):
                for signum in signals:
                    self.assertIs(signal.getsignal(signum), handler)
                raise RuntimeError("fixture")
        self.assertEqual({signum: signal.getsignal(signum) for signum in signals}, previous)

    def test_subreaper_failure_executes_once_but_task_stays_untracked(self):
        task_id, path = storage.create(self.bulk, self.output)
        receiver, sender = socket.socketpair()
        code = ("import importlib.util,sys; "
                f"s=importlib.util.spec_from_file_location('t',{str(HELPER)!r}); "
                "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m._subreaper=lambda:False; "
                "sys.exit(m.main())")
        command = ("import os; from pathlib import Path; "
                   "Path(os.environ['TMPDIR'],'calls').open('a').write('once\\n'); raise SystemExit(42)")
        worker = subprocess.Popen([sys.executable, "-c", code, "worker", "--id", task_id,
            "--bulk", str(self.bulk), "--output", str(self.output), "--result-fd", str(sender.fileno()),
            "--", sys.executable, "-c", command], pass_fds=(sender.fileno(),))
        sender.close()
        try:
            self.assertEqual(receiver.recv(32), b"42\n")
            self.assertEqual(worker.wait(timeout=10), 0)
        finally:
            receiver.close()
        self.assertEqual((path / "tmp/calls").read_text(), "once\n")
        self.assertFalse(self.read(task_id)["tracked"])
        self.assertEqual(storage.cleanup(self.bulk, self.output, True)["removed"], 0)


if __name__ == "__main__":
    unittest.main()
