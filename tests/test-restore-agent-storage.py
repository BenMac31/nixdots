import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "restore", Path(__file__).parents[1] / "scripts/restore-agent-storage.py")
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class Restoration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bootstrap = self.root / ("a" * 32 + "-agent-storage-bootstrap")
        self.bootstrap.mkdir()
        self.source = self.bootstrap / "desired"
        self.source.write_text("current storage")
        self.legacy = self.root / "legacy"
        self.legacy.write_text("legacy storage")
        self.live = self.root / "live"
        self.live.symlink_to(self.legacy)
        self.item = {"path": str(self.live), "source": str(self.source), "kind": "link",
                     "known_sha256": [restore.digest(self.legacy)]}
        self.manifest = {"version": 1, "bootstrap": str(self.bootstrap),
                         "files": [self.item], "migration_enabled": True}

    def test_known_activation_regression_is_restored_and_next_pass_is_noop(self):
        original_plan = restore.plan
        with patch.object(restore, "plan", side_effect=lambda m: original_plan(m, self.root)), \
                patch.object(restore.subprocess, "check_output", return_value="active\n"), \
                patch.object(restore.subprocess, "run"):
            self.assertEqual(restore.restore(self.manifest, "nix", "systemctl")["restored"], [str(self.live)])
            self.assertEqual(restore.restore(self.manifest, "nix", "systemctl")["restored"], [])
        self.assertEqual(self.live.read_text(), "current storage")

    def test_unknown_configuration_is_preserved_before_any_changes(self):
        other = self.root / "other"
        other.write_text("user changes")
        self.manifest["files"].append(dict(self.item, path=str(other)))
        with self.assertRaisesRegex(ValueError, "unrecognized changes"):
            restore.plan(self.manifest, self.root)
        self.assertEqual(self.live.read_text(), "legacy storage")
        self.assertEqual(other.read_text(), "user changes")

    def test_missing_link_is_recoverable_but_regular_file_is_not_overwritten(self):
        self.live.unlink()
        self.assertEqual(restore.plan(self.manifest, self.root), [self.item])
        self.live.write_text("legacy storage")
        with self.assertRaisesRegex(ValueError, "non-symlink preserved"):
            restore.plan(self.manifest, self.root)

    def test_home_manager_activation_defers_all_changes(self):
        with patch.object(restore.subprocess, "check_output", return_value="activating\n"), \
                patch.object(restore, "plan", side_effect=AssertionError("must wait")):
            self.assertIn("deferred", restore.restore(self.manifest, "nix", "systemctl"))

    def test_source_traversal_is_rejected(self):
        self.item["source"] = str(self.bootstrap) + "/../legacy"
        with self.assertRaisesRegex(ValueError, "outside rooted bootstrap"):
            restore.plan(self.manifest, self.root)


if __name__ == "__main__":
    unittest.main()
