import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE = Path(__file__).resolve().parents[1] / "modules/home-manager/desktop/env/wm/pomodoro/pomodoro.py"
spec = importlib.util.spec_from_file_location("pomodoro", MODULE)
pomodoro = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pomodoro)


class PomodoroTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "timer.json"
        self.notifications = []
        self.timer = pomodoro.Pomodoro(self.path, self.notifications.append)
        self.now = 1800000000

    def command(self, action, **values):
        self.timer.command(dict(action=action, **values), self.now)

    def finish(self):
        self.command("toggle")
        self.now += self.timer.state["remaining"]
        self.timer.tick(self.now)

    def test_pause_resume_and_restart_preserve_time(self):
        self.command("toggle")
        self.now += 123
        self.command("toggle")
        self.assertEqual(self.timer.seconds(self.now), 1377)
        self.timer = pomodoro.Pomodoro(self.path)
        self.now += 100
        self.assertEqual(self.timer.seconds(self.now), 1377)
        self.command("toggle")
        self.timer = pomodoro.Pomodoro(self.path)
        self.now += 10
        self.assertEqual(self.timer.seconds(self.now), 1367)

    def test_four_completed_focus_sessions_get_long_break(self):
        self.command("task", task="Write the report")
        for index in range(4):
            self.finish()
            self.assertEqual(self.timer.state["phase"], "long" if index == 3 else "short")
            self.assertIsNone(self.timer.state["deadline"])
            if index < 3:
                self.finish()
        state = self.timer.snapshot(self.now)
        self.assertEqual(state["todayCount"], 4)
        self.assertEqual(state["todayMinutes"], 100)
        self.assertEqual(state["history"][0]["task"], "Write the report")
        self.assertEqual(len(self.notifications), 7)

    def test_skip_and_reset_do_not_count_as_completed(self):
        self.command("toggle")
        self.now += 30
        self.command("reset")
        self.assertEqual(self.timer.seconds(self.now), 1500)
        self.assertIsNone(self.timer.state["deadline"])
        self.command("skip")
        self.assertEqual(self.timer.state["phase"], "short")
        self.assertEqual(self.timer.state["history"], [])

    def test_sleep_completes_only_one_session_with_auto_start(self):
        self.command("settings", settings={"autoFocus": True, "autoBreak": True})
        self.command("toggle")
        self.now += 86400
        self.timer = pomodoro.Pomodoro(self.path, self.notifications.append)
        self.timer.tick(self.now)
        self.assertEqual(self.timer.state["phase"], "short")
        self.assertEqual(len(self.timer.state["history"]), 1)
        self.assertEqual(self.timer.state["history"][0]["ended"], 1800001500)
        self.assertEqual(self.timer.seconds(self.now), 300)
        self.timer.tick(self.now)
        self.assertEqual(len(self.notifications), 1)

    def test_invalid_settings_are_atomic(self):
        for value in [0, 181, True, "25"]:
            with self.assertRaises(ValueError):
                self.command("settings", settings={"short": 8, "focus": value})
            self.assertEqual(self.timer.state["settings"], pomodoro.DEFAULTS)
        self.command("toggle")
        with self.assertRaises(ValueError):
            self.command("settings", settings={"focus": 40})

    def test_auto_start_requires_a_boolean(self):
        with self.assertRaises(ValueError):
            self.command("settings", settings={"autoFocus": 1})

    def test_auto_start_and_duration_change(self):
        self.command("settings", settings={"focus": 1, "short": 2, "autoBreak": True})
        self.assertEqual(self.timer.state["remaining"], 60)
        self.finish()
        self.assertIsNotNone(self.timer.state["deadline"])
        self.assertEqual(self.timer.seconds(self.now), 120)
        self.now += 120
        self.timer.tick(self.now)
        self.assertEqual(self.timer.state["phase"], "focus")
        self.assertIsNone(self.timer.state["deadline"])

    def test_statistics_use_local_day_and_history_is_newest_first(self):
        self.finish()
        self.command("phase", phase="focus")
        self.now += 86400
        self.finish()
        state = self.timer.snapshot(self.now)
        self.assertEqual(state["todayCount"], 1)
        self.assertEqual(len(state["history"]), 2)
        self.assertGreater(state["history"][0]["ended"], state["history"][1]["ended"])

    def test_corrupt_state_is_not_overwritten(self):
        self.path.write_text("not json")
        with self.assertRaises(ValueError):
            pomodoro.Pomodoro(self.path)
        self.assertEqual(self.path.read_text(), "not json")


if __name__ == "__main__":
    unittest.main()
