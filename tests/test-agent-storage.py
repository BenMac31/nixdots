import importlib.util
import contextlib
import io
import json
from concurrent.futures import ThreadPoolExecutor
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace


ROOT = Path(__file__).parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


storage = load("storage", "modules/home-manager/term/agent-storage.py")
mounts = load("mounts", "modules/nixos/agent-storage.py")


class Admission(unittest.TestCase):
    def test_status_ignores_legacy_estimates_when_disabled(self):
        args = SimpleNamespace(bulk=Path("/bulk"), output=Path("/output"),
                               minimum_free_gib=8, command_reserve_gib=0, output_limit_mib=8)
        tasks = SimpleNamespace(status=lambda *_: {}, reserved_bytes=lambda *_: 100 * storage.GIB)
        report = io.StringIO()
        with patch.object(storage, "ready"), patch.object(storage, "capacity_report", return_value={}), \
                patch.object(storage, "task_module", return_value=tasks), \
                patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(free=24 * storage.GIB)), \
                contextlib.redirect_stdout(report):
            storage.status(args)
        result = json.loads(report.getvalue())
        self.assertTrue(result["new_jobs_admitted"])
        self.assertFalse(result["bulk_admission"]["enabled"])
        self.assertEqual(result["bulk_admission"]["reserved_bytes"], 100 * storage.GIB)

    def test_disabled_estimates_do_not_block_on_existing_long_lived_tasks(self):
        tasks = load("disabled_budget_tasks", "modules/home-manager/term/agent-task-storage.py")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = SimpleNamespace(bulk=root / "bulk", output=root / "output",
                                   minimum_free_gib=8, command_reserve_gib=0)
            tasks.create(args.bulk, args.output, reservation_bytes=100 * storage.GIB)
            with patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(free=24 * storage.GIB)):
                task_id, path = storage.reserve_task(args, tasks)
            self.assertTrue(path.is_dir())
            with tasks._registry(args.output) as registry:
                self.assertEqual(tasks._read(registry, task_id)["reservation_bytes"], 0)

    def test_parallel_commands_share_admission_budget_and_completion_releases_it(self):
        tasks = load("budget_tasks", "modules/home-manager/term/agent-task-storage.py")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = SimpleNamespace(bulk=root / "bulk", output=root / "output",
                                   minimum_free_gib=8, command_reserve_gib=2)
            with patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(free=12 * storage.GIB)):
                with ThreadPoolExecutor(max_workers=8) as executor:
                    admitted = list(executor.map(lambda _: storage.reserve_task(args, tasks), range(8)))
                leases = [result for result in admitted if result]
                self.assertEqual(len(leases), 2)
                self.assertEqual(tasks.reserved_bytes(args.bulk, args.output), 4 * storage.GIB)
                task_id, _ = leases[0]
                with tasks._registry(args.output) as registry, tasks._lock(registry, task_id):
                    record = tasks._read(registry, task_id)
                    record["completed"] = True
                    tasks._write(registry, task_id, record)
                self.assertIsNotNone(storage.reserve_task(args, tasks))
                self.assertIsNone(storage.reserve_task(args, tasks))

    def test_a_new_session_does_not_inherit_the_parent_command_bypass(self):
        args = SimpleNamespace(bulk=Path("/bulk"), output=Path("/output"), bwrap="bwrap", argv=["--", "agent"])
        with patch.object(storage, "ready"), patch.dict(os.environ, {"AGENT_STORAGE_COMMAND": "1"}), \
                patch.object(storage.os, "execvpe", side_effect=RuntimeError("exec intercepted")) as execute:
            with self.assertRaisesRegex(RuntimeError, "exec intercepted"):
                storage.session(args)
        environment = execute.call_args.args[2]
        self.assertNotIn("AGENT_STORAGE_COMMAND", environment)
        self.assertEqual(environment["TMPDIR"], "/output/tmp")
        self.assertIn(["--bind", "/output/tmp", "/tmp"],
                      [execute.call_args.args[1][i:i + 3] for i in range(len(execute.call_args.args[1]) - 2)])

    def test_full_bulk_rejects_new_builds_but_permits_recovery(self):
        self.assertFalse(storage.admitted(["zsh", "-c", "cargo build"], 0, 8))
        self.assertTrue(storage.admitted(["zsh", "-c", "rm cache.tar"], 0, 8))
        self.assertTrue(storage.admitted(["zsh", "-c", "agent-storage cleanup"], 0, 8))
        self.assertTrue(storage.admitted(["zsh", "-c", "cargo build"], 8, 8))
        self.assertTrue(storage.admitted(["df", "-h"], 0, 8))

    def test_recovery_does_not_need_an_output_budget(self):
        args = SimpleNamespace(bulk=Path("/bulk"), output=Path("/output"), bwrap="bwrap",
                               argv=["--", "zsh", "-c", "agent-storage cleanup"],
                               minimum_free_gib=8, output_limit_mib=8)
        with patch.object(storage, "ready"), patch.object(storage, "request_cleanup") as request, \
                patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(free=0)), \
                patch.object(storage, "output_slot", side_effect=AssertionError("recovery needs no slot")), \
                patch.object(storage, "relay", return_value=0) as relay:
            self.assertEqual(storage.command(args), 0)
        self.assertEqual(relay.call_count, 1)
        request.assert_not_called()

    def test_cleanup_service_failure_does_not_prevent_recovery(self):
        with patch.object(storage.subprocess, "run", side_effect=OSError("bus unavailable")):
            self.assertFalse(storage.request_cleanup())

    def test_output_reserve_cannot_share_the_bulk_filesystem(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(storage.os.path, "ismount", return_value=True):
            with self.assertRaisesRegex(RuntimeError, "separate filesystem"):
                storage.ready(Path(temp), Path(temp))

    def test_missing_mount_never_falls_back_to_the_host_disk(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(RuntimeError, "unavailable"):
                storage.ready(Path(temp), Path(temp))


BWRAP = os.environ.get("AGENT_STORAGE_BWRAP") or shutil.which("bwrap")


@unittest.skipUnless(BWRAP, "requires bubblewrap")
class DeviceAccess(unittest.TestCase):
    def test_full_disposable_bulk_keeps_session_tmp_and_reporting_writable(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bulk, output = root / "bulk", root / "output"
            bulk.mkdir()
            (output / "tmp").mkdir(parents=True)
            loader = (
                "import importlib.util,os,sys,errno; from pathlib import Path; from types import SimpleNamespace; "
                f"s=importlib.util.spec_from_file_location('s',{str(ROOT / 'modules/home-manager/term/agent-storage.py')!r}); "
                "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.request_cleanup=lambda:False; "
                f"bulk=Path({str(bulk)!r});output=Path({str(output)!r}); "
            )
            probe = loader + (
                f"a=SimpleNamespace(bulk=bulk,output=output,bwrap={BWRAP!r},minimum_free_gib=8,"
                "output_limit_mib=1,argv=[sys.executable,'-c','raise SystemExit(99)']); "
                "assert m.command(a)==75; "
                "Path('/tmp/agent-still-alive').write_text('communicating'); "
                "assert Path(os.environ['TMPDIR'],'agent-still-alive').read_text()=='communicating'; "
                "print('agent still communicates after full bulk')"
            )
            setup = loader + (
                "(output/'tmp').mkdir(); "
                "\nfor name in ('tmp','var-tmp','home/.cache','.output-reserve'):\n"
                "    (bulk/name).mkdir(parents=True,exist_ok=True)\n"
                "with (bulk/'fill').open('wb',buffering=0) as stream:\n"
                "    try:\n"
                "        while True: stream.write(bytes(65536))\n"
                "    except OSError as error: assert error.errno==errno.ENOSPC\n"
                f"a=SimpleNamespace(bulk=bulk,output=output,bwrap={BWRAP!r},"
                f"argv=[sys.executable,'-c',{probe!r}]);m.session(a)"
            )
            result = subprocess.run(
                [BWRAP, "--bind", "/", "/", "--dev-bind", "/dev", "/dev",
                 "--size", str(1024**2), "--tmpfs", str(bulk),
                 "--size", str(2 * 1024**2), "--tmpfs", str(output), "--", sys.executable, "-c", setup],
                capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("agent still communicates", result.stdout)

    def test_devices_work_in_sessions_and_nested_commands(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bulk, output = root / "bulk", root / "output"
            for path in (bulk / "tmp", bulk / "var-tmp", bulk / "home/.cache", output / "tmp"):
                path.mkdir(parents=True, exist_ok=True)
            (bulk / ".output-reserve").touch()
            code = (
                "import importlib.util,sys; from pathlib import Path; from types import SimpleNamespace; "
                f"s=importlib.util.spec_from_file_location('s',{str(ROOT / 'modules/home-manager/term/agent-storage.py')!r}); "
                "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.ready=lambda *args:None; "
                f"a=SimpleNamespace(bulk=Path({str(bulk)!r}),output=Path({str(output)!r}),"
                f"bwrap={BWRAP!r},minimum_free_gib=0,output_limit_mib=1,argv=sys.argv[2:]); "
                "sys.exit(getattr(m,sys.argv[1])(a))"
            )
            probe = (
                "import os; "
                "f=os.open('/dev/null',os.O_RDWR);os.close(f); "
                "f=os.open('/dev/urandom',os.O_RDONLY);assert len(os.read(f,16))==16;os.close(f); "
                "print('devices work')"
            )
            # The outer session and the command's second mount namespace must both preserve devices.
            for nested in (False, True):
                with self.subTest(nested_command=nested):
                    argv = [sys.executable, "-c", probe]
                    if nested:
                        argv = [sys.executable, "-c", code, "command", *argv]
                    result = subprocess.run([sys.executable, "-c", code, "session", *argv],
                                            capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), "devices work")


class OutputLimits(unittest.TestCase):
    def test_output_budget_defers_commands_without_consuming_the_last_headroom(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(storage, "request_cleanup"):
            output = Path(temp)
            with patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(free=storage.OUTPUT_HEADROOM)):
                with self.assertRaisesRegex(RuntimeError, "agent can keep communicating"):
                    with storage.output_slot(output, 1024):
                        self.fail("an exhausted output pool admitted work")
            with patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(free=storage.GIB)):
                with storage.output_slot(output, 1024):
                    self.assertEqual(len(list((output / "state/output-jobs").iterdir())), 1)
            self.assertEqual(list((output / "state/output-jobs").iterdir()), [])

    def test_both_streams_are_capped_drained_and_exit_status_is_preserved(self):
        code = (
            "import importlib.util,os,sys; "
            f"s=importlib.util.spec_from_file_location('s',{str(ROOT / 'modules/home-manager/term/agent-storage.py')!r}); "
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m); "
            "sys.exit(m.relay([sys.executable,'-c',"
            "\"import os;os.write(1,b'x'*200000);os.write(2,b'y'*200000);raise SystemExit(42)\"],dict(os.environ),1024))"
        )
        result = subprocess.run([sys.executable, "-c", code], capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 42)
        for data, byte in ((result.stdout, b"x"), (result.stderr, b"y")):
            self.assertTrue(data.startswith(byte * 1024))
            self.assertLess(len(data), 1300)
            self.assertEqual(data.count(b"output limit reached"), 1)


class Images(unittest.TestCase):
    def test_existing_image_with_wrong_size_is_never_reformatted(self):
        with tempfile.TemporaryDirectory() as temp:
            image = Path(temp) / "output.img"
            image.write_bytes(b"existing data")
            with self.assertRaisesRegex(RuntimeError, "refusing to replace"):
                mounts.reserve_image(image, 8, os.getuid(), os.getgid())
            self.assertEqual(image.read_bytes(), b"existing data")

    def test_existing_unknown_filesystem_is_never_formatted(self):
        with patch.object(mounts, "run", return_value="TYPE=btrfs\nUUID=test"):
            with self.assertRaisesRegex(RuntimeError, "refusing to mount or format"):
                mounts.identity(Path("some-image"))


class Cleanup(unittest.TestCase):
    def test_abandoned_response_cache_writes_are_removed_without_touching_active_or_unknown_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bulk, output = root / "bulk", root / "output"
            cache = bulk / "tmp/ghc/cache"
            cache.mkdir(parents=True)
            output.mkdir()
            stale = cache / ("a" * 64 + ".json.999999999")
            active = cache / ("b" * 64 + ".json." + str(os.getpid()))
            recent = cache / ("c" * 64 + ".json.999999998")
            unknown = cache / "source.json.999999997"
            for path in (stale, active, recent, unknown):
                path.write_text("temporary cache or retained data")
            now = time.time() + 7200
            os.utime(recent, (now, now))
            args = SimpleNamespace(bulk=bulk, output=output, cleanup_free_gib=32)
            with patch.object(storage, "ready"), patch.object(storage.time, "time", return_value=now), \
                    patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(
                        total=128 * storage.GIB, used=64 * storage.GIB, free=64 * storage.GIB)):
                storage.cleanup(args)
            self.assertFalse(stale.exists())
            for path in (active, recent, unknown):
                self.assertTrue(path.exists())

    def test_low_space_cleanup_does_not_launch_heavy_workspace_scans(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = SimpleNamespace(bulk=root, output=root, cleanup_free_gib=32)
            with patch.object(storage, "ready"), \
                    patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(
                        total=128 * storage.GIB, used=127 * storage.GIB, free=storage.GIB)), \
                    patch.object(storage.shutil, "which", return_value=None), \
                    patch.object(storage.subprocess, "run") as run:
                storage.cleanup(args)
            run.assert_not_called()

    def test_readonly_command_cleanup_delegates_to_host_service(self):
        args = SimpleNamespace(bulk=Path("/bulk"), output=Path("/output"))
        with patch.object(storage, "ready"), patch.dict(os.environ, {"AGENT_STORAGE_COMMAND": "1"}), \
                patch.object(storage.os, "access", return_value=False), \
                patch.object(storage, "request_cleanup", return_value=True) as request:
            storage.cleanup(args)
        request.assert_called_once_with()

    def test_open_outputs_and_non_cache_data_are_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bulk, output = root / "bulk", root / "output"
            cache = bulk / "tmp/ghc/cache/answer.json"
            closed = output / "tmp/claude-1000/tasks/closed.output"
            opened = closed.with_name("open.output")
            source = bulk / "tmp/source.txt"
            for path in (cache, closed, opened, source):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("keep source or regenerate cache")
            args = SimpleNamespace(bulk=bulk, output=output, cleanup_free_gib=32)
            with opened.open(), patch.object(storage, "ready"), \
                    patch.object(storage.time, "time", return_value=time.time() + 2 * 86400), \
                    patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(
                        total=128 * storage.GIB, used=64 * storage.GIB, free=64 * storage.GIB)):
                storage.cleanup(args)
            self.assertFalse(cache.exists())
            self.assertFalse(closed.exists())
            self.assertTrue(opened.exists())
            self.assertTrue(source.exists())


class Capacity(unittest.TestCase):
    def test_samples_keep_a_bounded_history(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = SimpleNamespace(bulk=root, output=root)
            storage.capacity_report(args, sample=True)
            history = root / "state/capacity-history.jsonl"
            self.assertEqual(len(history.read_text().splitlines()), 1)
            history.write_text("x" * 1024**2)
            storage.capacity_report(args, sample=True)
            self.assertEqual(history.with_suffix(".jsonl.1").stat().st_size, 1024**2)
            self.assertEqual(len(history.read_text().splitlines()), 1)

    def test_growth_estimate_and_inodes_are_reported_without_scanning_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args = SimpleNamespace(bulk=root, output=root)
            used = storage.GIB
            def usage(_):
                return SimpleNamespace(total=10 * storage.GIB, used=used, free=10 * storage.GIB - used)
            with patch.object(storage.shutil, "disk_usage", side_effect=usage), \
                    patch.object(storage.time, "monotonic", return_value=100):
                first = storage.capacity_report(args, sample=True)
            self.assertIsNone(first["bulk"]["growth_bytes_per_second"])
            used = 2 * storage.GIB
            with patch.object(storage.shutil, "disk_usage", side_effect=usage), \
                    patch.object(storage.time, "monotonic", return_value=160):
                second = storage.capacity_report(args)
            self.assertAlmostEqual(second["bulk"]["growth_bytes_per_second"], storage.GIB / 60, places=2)
            self.assertEqual(second["bulk"]["estimated_seconds_until_full"], 480)
            self.assertIn("free_inodes", second["bulk"])


class BuildCaches(unittest.TestCase):
    def test_go_prune_retains_open_recent_unknown_and_symlinked_data(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "go-build"
            shard = root / "ab"
            shard.mkdir(parents=True)
            old, opened, recent = [shard / (letter * 64 + "-d") for letter in "abc"]
            source = shard / "source.go"
            target = Path(temp) / "source"
            for path in (old, opened, recent, source, target):
                path.write_bytes(b"source or cache" * 1024)
            now = time.time()
            for path in (old, opened):
                os.utime(path, (now - 7200, now - 7200))
            linked = shard / ("d" * 64 + "-d")
            linked.symlink_to(target)
            info = opened.stat()
            # A bind alias can have a different path but the same identity.
            result = storage.prune_go_cache(root, 0, {(info.st_dev, info.st_ino)}, now)
            self.assertGreater(result["removed_bytes"], 0)
            self.assertFalse(old.exists())
            for path in (opened, recent, source, linked, target):
                self.assertTrue(path.exists())

    def test_uv_pruning_uses_the_cache_protocol_and_only_under_pressure(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cache = root / "home/.cache/uv"
            cache.mkdir(parents=True)
            args = SimpleNamespace(bulk=root, cleanup_free_gib=32, cache_cleanup=True, uv="uv")
            with patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(free=31 * storage.GIB)), \
                    patch.object(storage.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
                self.assertEqual(storage.prune_build_caches(args, set(), time.time())["uv"], {"returncode": 0})
                self.assertEqual(run.call_args.args[0], ["uv", "cache", "prune", "--cache-dir", str(cache)])
                self.assertEqual(run.call_args.kwargs["env"]["UV_LOCK_TIMEOUT"], "0")
            with patch.object(storage.shutil, "disk_usage", return_value=SimpleNamespace(free=32 * storage.GIB)), \
                    patch.object(storage.subprocess, "run") as run:
                self.assertEqual(storage.prune_build_caches(args, set(), time.time()), {})
                run.assert_not_called()


class ShellOptions(unittest.TestCase):
    def test_wrapped_shells_keep_options_and_positional_arguments(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            wrapper = root / "bin/agent-storage"
            wrapper.parent.mkdir()
            wrapper.write_text(
                f"#!{sys.executable}\nimport os,sys\n"
                "assert sys.argv[1:3]==['command','--']\n"
                "os.environ['AGENT_STORAGE_COMMAND']='1'\n"
                "os.execvpe(sys.argv[3],sys.argv[3:],os.environ)\n")
            wrapper.chmod(0o700)
            bash_source = (ROOT / "modules/home-manager/term/agent-scratch.nix").read_text()
            bash_hook = bash_source.split('bashInit = pkgs.writeText "agent-storage-bash-env" \'\'\n', 1)[1].split("  '';", 1)[0]
            zsh_source = (ROOT / "modules/home-manager/term/ai/accounts.nix").read_text()
            zsh_hook = re.search(r'      if \[\[ -n .*?      fi', zsh_source, re.S).group()
            for name, hook in (("bash", bash_hook), ("zsh", zsh_hook)):
                shell = shutil.which(name)
                if not shell:
                    continue
                hook = hook.replace("${runtime}/bin/agent-storage", str(wrapper))
                hook = hook.replace("${storageCommand}", str(wrapper))
                hook = hook.replace("${pkgs." + name + "}/bin/" + name, shell).replace("''${", "${")
                hook_file = root / ("bash-env" if name == "bash" else ".zshenv")
                hook_file.write_text(hook)
                env = dict(os.environ, AGENT_STORAGE_SESSION="1")
                env.pop("AGENT_STORAGE_COMMAND", None)
                if name == "bash":
                    env["BASH_ENV"] = str(hook_file)
                else:
                    env["ZDOTDIR"] = str(root)
                    env.pop("BASH_ENV", None)
                with self.subTest(shell=name, flags=True):
                    result = subprocess.run([shell, "-eu", "-c", "false; echo option-lost"],
                                            env=env, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertNotIn("option-lost", result.stdout)
                with self.subTest(shell=name, arguments=True):
                    result = subprocess.run([shell, "-c", 'printf "%s\\n" "$0" "$@"',
                                             "custom zero", "first with space", "second\nline"],
                                            env=env, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "custom zero\nfirst with space\nsecond\nline\n")


@unittest.skipUnless(os.geteuid() == 0 and os.environ.get("AGENT_STORAGE_INTEGRATION") == "1",
                     "requires explicit root integration test")
class ReserveIsolation(unittest.TestCase):
    def test_output_remains_writable_when_bulk_is_completely_full(self):
        # These disposable filesystems are created inside the real scratch pool.
        with tempfile.TemporaryDirectory(prefix="storage-test-", dir="/var/lib/agent-scratch") as temp:
            root = Path(temp)
            outer, inner = root / "outer", root / "inner"
            image = root / "test.img"
            with image.open("wb") as stream:
                os.posix_fallocate(stream.fileno(), 0, 128 * 1024**2)
            mounts.run("mkfs.ext4", "-q", "-F", "-m", "0", image)
            try:
                mounts.mount_image(image, outer)
                with patch.object(mounts, "GIB", 1024**2):
                    mounts.reserve_image(outer / "output.img", 32, 0, 0)
                mounts.mount_image(outer / "output.img", inner)
                with (outer / "fill").open("wb", buffering=0) as stream:
                    block = bytes(1024**2)
                    with self.assertRaises(OSError):
                        while True:
                            stream.write(block)
                data = b"protected output\n" * 65536
                (inner / "proof").write_bytes(data)
                with (inner / "proof").open("rb") as stream:
                    os.fsync(stream.fileno())
                self.assertEqual((inner / "proof").read_bytes(), data)
            finally:
                for target in (inner, outer):
                    if os.path.ismount(target):
                        mounts.run("umount", target)


if __name__ == "__main__":
    unittest.main()
