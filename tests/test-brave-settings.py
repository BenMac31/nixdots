import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "brave_settings",
    Path(__file__).parents[1] / "modules/home-manager/desktop/apps/brave-settings.py",
)
settings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(settings)


class BraveSettingsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.path = self.root / "Default/Preferences"
        self.path.parent.mkdir()

    def test_recognizes_flatpak_process_titles(self):
        expected = ["/app/brave/brave", "--user-data-dir=/tmp/profile", "--no-first-run"]
        self.assertEqual(settings.arguments((" ".join(expected) + "\0").encode()), expected)
        self.assertEqual(settings.arguments(("\0".join(expected) + "\0").encode()), expected)

    def test_preserves_unmanaged_data_and_original_backup(self):
        original = {"brave": {"tabs": {"old": True}}, "unmanaged": [1, 2]}
        self.path.write_text(json.dumps(original))
        settings.update(self.path, {"brave": {"tabs": {"enabled": True}}})
        self.assertEqual(json.loads(self.path.read_text()), {
            "brave": {"tabs": {"old": True, "enabled": True}}, "unmanaged": [1, 2],
        })
        backup = self.path.with_name("Preferences.before-nix-browser")
        self.assertEqual(json.loads(backup.read_text()), original)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        before = self.path.stat().st_mtime_ns
        settings.update(self.path, {"brave": {"tabs": {"enabled": True}}})
        self.assertEqual(self.path.stat().st_mtime_ns, before)
        settings.update(self.path, {"brave": {"tabs": {"enabled": False}}})
        self.assertEqual(json.loads(backup.read_text()), original)

    def test_invalid_json_is_left_untouched(self):
        self.path.write_text("truncated")
        with self.assertRaises(json.JSONDecodeError):
            settings.update(self.path, {"managed": True})
        self.assertEqual(self.path.read_text(), "truncated")

    def test_refuses_symlinks(self):
        target = self.root / "other"
        target.write_text("{}")
        self.path.symlink_to(target)
        with self.assertRaises(RuntimeError):
            settings.update(self.path, {"managed": True})
        self.assertEqual(target.read_text(), "{}")

    def test_running_browser_is_not_modified(self):
        config = self.root / "settings.json"
        config.write_text(json.dumps({"preferences": {"managed": True}, "localState": {}}))
        self.path.write_text("{}")
        with patch.object(settings, "running", return_value=True), patch.object(
            settings.sys, "argv", ["brave-settings", str(config), str(self.root)]
        ):
            settings.main()
        self.assertEqual(self.path.read_text(), "{}")
        self.assertFalse((self.root / "Local State").exists())


if __name__ == "__main__":
    unittest.main()
