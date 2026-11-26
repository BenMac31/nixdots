import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "disk_watch", Path(__file__).parents[1] / "modules/home-manager/term/disk-watch.py"
)
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)


class DiskWatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.state = Path(self.temp.name)
        self.reserve = self.state / "ballast"
        self.m = dict(available_bytes=300 * watch.GIB, unallocated_bytes=80 * watch.GIB,
                      metadata_used_percent=70, read_only=False)

    def run_check(self, freeze_agents=False, **changes):
        self.m.update(changes)
        with patch.object(watch, "metrics", return_value=self.m), patch.object(watch, "ctl") as ctl, patch.object(watch.shutil, "which", return_value=None):
            ctl.return_value.stdout = "running\n"
            result = watch.check("/", self.state, self.reserve, freeze_agents=freeze_agents)
        return result, ctl

    def test_thresholds_include_allocator_and_read_only(self):
        cases = [({}, "OK"), ({"available_bytes": 200 * watch.GIB}, "LOW"),
                 ({"available_bytes": 95 * watch.GIB}, "CRITICAL"),
                 ({"available_bytes": 191 * watch.GIB}, "CRITICAL"),
                 ({"unallocated_bytes": 23 * watch.GIB}, "CRITICAL"),
                 ({"unallocated_bytes": 31 * watch.GIB, "metadata_used_percent": 90}, "CRITICAL"),
                 ({"read_only": True}, "READ_ONLY")]
        for changes, expected in cases:
            with self.subTest(changes=changes):
                self.assertEqual(watch.classify(self.m | changes), expected)

    def test_critical_releases_reserve_and_keeps_sessions_running(self):
        self.reserve.touch()
        result, ctl = self.run_check(available_bytes=95 * watch.GIB)
        self.assertFalse(self.reserve.exists())
        self.assertNotIn(unittest.mock.call("freeze", "agents.slice"), ctl.call_args_list)
        ctl.assert_any_call("start", "--no-block", "disk-watch-gc.service")
        self.assertFalse(result["automatic_freeze"])
        self.assertEqual(json.loads((self.state / "state.json").read_text()), result)

    def test_freezing_requires_explicit_opt_in(self):
        _, ctl = self.run_check(freeze_agents=True, available_bytes=95 * watch.GIB)
        ctl.assert_any_call("freeze", "agents.slice")

    def test_gc_is_async_and_rate_limited(self):
        _, ctl = self.run_check(available_bytes=200 * watch.GIB)
        ctl.assert_any_call("start", "--no-block", "disk-watch-gc.service")
        _, ctl = self.run_check()
        self.assertNotIn(unittest.mock.call("start", "--no-block", "disk-watch-gc.service"), ctl.call_args_list)

    def test_failed_freeze_is_visible_in_state(self):
        self.m["available_bytes"] = 90 * watch.GIB
        with patch.object(watch, "metrics", return_value=self.m), patch.object(watch, "ctl") as ctl, patch.object(watch.shutil, "which", return_value=None):
            ctl.side_effect = subprocess.TimeoutExpired("systemctl", 10)
            with self.assertRaises(RuntimeError):
                watch.check("/", self.state, self.reserve, freeze_agents=True)
        state = json.loads((self.state / "state.json").read_text())
        self.assertTrue(state["errors"])
        self.assertEqual(state["state"], "CRITICAL")

    def test_recovery_does_not_thaw_agents(self):
        _, ctl = self.run_check()
        self.assertNotIn(unittest.mock.call("thaw", "agents.slice"), ctl.call_args_list)

    def test_read_only_reserve_failure_still_freezes_agents(self):
        self.reserve.touch()
        self.m["read_only"] = True
        with patch.object(watch, "metrics", return_value=self.m), patch.object(watch, "ctl") as ctl, patch.object(watch.shutil, "which", return_value=None):
            ctl.return_value.stdout = "frozen\n"
            def cannot_delete():
                ctl.assert_any_call("freeze", "agents.slice")
                raise OSError("Read-only file system")
            with patch.object(Path, "unlink", side_effect=cannot_delete):
                with self.assertRaises(RuntimeError):
                    watch.check("/", self.state, self.reserve, freeze_agents=True)
            ctl.assert_any_call("freeze", "agents.slice")
        self.assertEqual(json.loads((self.state / "state.json").read_text())["state"], "READ_ONLY")


if __name__ == "__main__":
    unittest.main()
