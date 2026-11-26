import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "switch_check", ROOT / "modules/nixos/agent-storage-switch-check.py"
)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

FSTAB = """/var/lib/agent-scratch/tmp /tmp none bind,x-systemd.requires=agent-storage.service 0 0
/var/lib/agent-scratch/var-tmp /var/tmp none bind,x-systemd.requires=agent-storage.service 0 0
"""


class SwitchCheck(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.current = self.root / "current"
        self.incoming = self.root / "incoming"
        for system in [self.current, self.incoming]:
            unit = system / "etc/systemd/system/agent-storage.service"
            unit.parent.mkdir(parents=True)
            unit.write_text("[Service]\nX-RestartIfChanged=false\n")
            (system / "etc/fstab").write_text(FSTAB)
        self.fstab = self.current / "etc/fstab"

    def check(self, action="switch"):
        guard.check(self.incoming, action, self.current, self.fstab)

    def test_unchanged_mounts_allow_service_updates(self):
        (self.incoming / "etc/systemd/system/agent-storage.service").write_text(
            "[Service]\nExecStart=/new/prepare\nX-RestartIfChanged=false\n"
        )
        self.check()

    def test_changed_mount_source_rejects_switch_and_test(self):
        (self.incoming / "etc/fstab").write_text(FSTAB.replace("agent-scratch", "other"))
        for action in ["switch", "test", "check"]:
            with self.subTest(action=action), self.assertRaisesRegex(RuntimeError, "Refusing live"):
                self.check(action)

    def test_disabling_storage_rejects_live_mount_removal(self):
        (self.incoming / "etc/systemd/system/agent-storage.service").unlink()
        (self.incoming / "etc/fstab").write_text("")
        with self.assertRaises(RuntimeError):
            self.check()

    def test_adding_storage_requires_boot(self):
        self.fstab.write_text("")
        (self.current / "etc/systemd/system/agent-storage.service").unlink()
        with self.assertRaises(RuntimeError):
            self.check()

    def test_boot_and_preview_allow_layout_changes(self):
        (self.incoming / "etc/fstab").write_text("")
        self.check("boot")
        self.check("dry-activate")

    def test_option_order_and_comments_do_not_require_reboot(self):
        (self.incoming / "etc/fstab").write_text(
            "# generated\n" + FSTAB.replace(
                "bind,x-systemd.requires=agent-storage.service",
                "x-systemd.requires=agent-storage.service,bind",
            )
        )
        self.check()

    def test_missing_incoming_fstab_fails_closed(self):
        (self.incoming / "etc/fstab").unlink()
        with self.assertRaises(FileNotFoundError):
            self.check()


if __name__ == "__main__":
    unittest.main()
