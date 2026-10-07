"""Run with the patched hackerboard API on PYTHONPATH."""
import sqlite3
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

from hackerboard.board import Board
from hackerboard.config import Config
from hackerboard.store import Store


class DailyActivityTests(unittest.TestCase):
    def test_totals_preserve_upstream_activity_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = Store(Path(tmp) / "activity.db")
            self.addCleanup(store.close)
            row = {
                "day": "2026-09-27", "active_accounts": 2, "active_installs": 3,
                "new_accounts": 1, "total_accounts": 10,
                "active_hours": 1.5, "hands_on_hours": 0.5,
                "prompters": 2, "heavy_prompters": 1, "prompts": 12,
            }
            store.record_daily_activity([row])
            self.assertEqual(store.daily_activity(), [row])

    def test_old_cache_migrates_and_survives_old_writer(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "old.db"
            with sqlite3.connect(path) as db:
                db.execute("CREATE TABLE daily_activity (day TEXT PRIMARY KEY, active_accounts INTEGER NOT NULL, active_installs INTEGER NOT NULL, new_accounts INTEGER NOT NULL, fetched REAL NOT NULL)")
                db.execute("INSERT INTO daily_activity VALUES ('2026-09-20', 2, 3, 1, 0)")
            store = Store(path)
            row = store.daily_activity()[0]
            self.assertIsNone(row["total_accounts"])
            self.assertEqual(row["active_accounts"], 2)
            store.record_daily_activity([row | {"total_accounts": 10}])
            # Rolling back to an older writer must not erase known totals.
            row.pop("total_accounts")
            store.record_daily_activity([row | {"active_accounts": 4}])
            store.close()
            store = Store(path)
            self.assertEqual(store.daily_activity()[0]["total_accounts"], 10)
            self.assertEqual(store.daily_activity()[0]["active_accounts"], 4)
            store.close()

    def test_daily_values_are_raw_counts_in_date_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            board = Board(Config(data_dir=Path(tmp)))
            rows = [
                {"day": (date(2026, 8, 1) + timedelta(days=i)).isoformat(),
                 "active_accounts": i % 5, "active_installs": 100,
                 "new_accounts": 1, "total_accounts": 10 + i}
                for i in range(35)
            ]
            board.store.record_daily_activity(list(reversed(rows)))
            points = board.growth()["daily_activity"]
            self.assertEqual(len(points), 28)
            self.assertEqual(points, [
                {"day": r["day"], "users": r["total_accounts"], "dau": r["active_accounts"]}
                for r in rows[-28:]
            ])
            board.store.close()


if __name__ == "__main__":
    unittest.main()
