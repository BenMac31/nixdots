import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "scratch", Path(__file__).parents[1] / "modules/home-manager/term/agent-scratch.py")
scratch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scratch)


class ScratchMigration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.source = self.home / "Projects/wt"
        self.source.mkdir(parents=True)
        (self.source / "source").write_text("unpublished local source\n")
        (self.source / "link").symlink_to("source")
        self.alias = self.base / "mounted"
        self.alias.mkdir()
        self.state = self.base / "state"
        self.state.mkdir()
        self.dest = self.alias / "home/Projects/wt"
        space = patch.object(scratch.shutil, "disk_usage", return_value=SimpleNamespace(free=64 * scratch.GIB))
        space.start()
        self.addCleanup(space.stop)

    def migrate(self, paths=(), refresh=lambda: (), apply=True):
        return scratch.migrate_one(self.home, "Projects/wt", self.alias, paths,
                                   self.state, refresh, apply)

    def test_verified_copy_and_atomic_cutover_preserve_local_files_and_links(self):
        self.assertEqual(self.migrate(), "capped; verified old data removed")
        self.assertTrue(self.source.is_symlink())
        self.assertEqual((self.source / "source").read_text(), "unpublished local source\n")
        self.assertEqual((self.dest / "link").readlink(), Path("source"))
        self.assertEqual(list(self.source.parent.glob(".wt.pre-scratch-*")), [])

    def test_plan_changes_nothing(self):
        self.assertTrue(self.migrate(apply=False).startswith("ready:"))
        self.assertFalse(self.source.is_symlink())
        self.assertFalse(self.dest.exists())

    def test_active_source_is_never_moved(self):
        self.assertEqual(self.migrate(paths=[str(self.source / "source")]), "active source retained")
        self.assertFalse(self.source.is_symlink())

    def test_active_sources_beneath_a_symlinked_parent_are_never_moved(self):
        alias = self.base / "alias-home"
        alias.symlink_to(self.home, target_is_directory=True)
        result = scratch.migrate_one(alias, "Projects/wt", self.alias,
                                     [str(self.source / "source")], self.state, lambda: (), True)
        self.assertEqual(result, "active source retained")
        self.assertFalse(self.source.is_symlink())

    def test_source_becoming_active_aborts_unpublished_copy(self):
        result = self.migrate(refresh=lambda: [str(self.source)])
        self.assertEqual(result, "source became active; original retained")
        self.assertFalse(self.source.is_symlink())
        self.assertFalse(self.dest.exists())
        self.assertEqual(list(self.dest.parent.glob(".stage-*")), [])

    def test_existing_destination_data_is_never_overwritten(self):
        self.dest.mkdir(parents=True)
        (self.dest / "unique").write_text("other local work")
        self.assertIn("existing destination retained", self.migrate())
        self.assertEqual((self.dest / "unique").read_text(), "other local work")
        self.assertFalse(self.source.is_symlink())

    def test_capacity_guard_keeps_original(self):
        with patch.object(scratch.shutil, "disk_usage", return_value=SimpleNamespace(free=1024)):
            self.assertTrue(self.migrate().startswith("does not fit:"))
        self.assertFalse(self.source.is_symlink())

    def test_migration_cannot_consume_cleanup_headroom(self):
        with patch.object(scratch.shutil, "disk_usage", return_value=SimpleNamespace(free=24 * scratch.GIB)):
            self.assertTrue(self.migrate().startswith("does not fit:"))
        self.assertFalse(self.dest.exists())
        self.assertFalse(self.source.is_symlink())

    def test_repeat_migration_is_idempotent(self):
        self.migrate()
        self.assertEqual(self.migrate(), "already capped")

    def test_open_old_copy_is_retained_after_cutover(self):
        calls = 0
        def refresh():
            nonlocal calls
            calls += 1
            return list(map(str, self.source.parent.glob(".wt.pre-scratch-*"))) if calls > 1 else []
        self.assertIn("old copy still open", self.migrate(refresh=refresh))
        backup = next(self.source.parent.glob(".wt.pre-scratch-*"))
        self.assertEqual((backup / "source").read_text(), "unpublished local source\n")
        self.assertTrue(self.source.is_symlink())

    def test_relative_paths_cannot_escape_home(self):
        for name in ["/etc", "../other", "Projects/../../other", "", "."]:
            with self.assertRaises(ValueError):
                scratch.validate_relative(name)

    def test_readonly_dependency_directories_can_be_retired_after_verification(self):
        d = self.source / "readonly"
        d.mkdir()
        (d / "module").write_text("dependency")
        d.chmod(0o555)
        self.assertEqual(self.migrate(), "capped; verified old data removed")
        self.assertEqual((self.source / "readonly/module").read_text(), "dependency")

    def test_existing_image_is_never_reformatted_to_another_size(self):
        store = self.state / "store"
        store.mkdir()
        image = store / "scratch.img"
        image.write_bytes(b"existing data")
        with self.assertRaisesRegex(RuntimeError, "size differs"):
            scratch.create(self.state, 128)
        self.assertEqual(image.read_bytes(), b"existing data")


class WorkspaceBoundaries(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.root = self.home / "Projects/wt"
        (self.root / "existing").mkdir(parents=True)
        (self.root / "existing/file").write_text("unpublished work")
        self.alias = self.base / "scratch"
        self.alias.mkdir()
        self.state = self.base / "state"
        self.state.mkdir()
        self.space = patch.object(scratch.shutil, "disk_usage", return_value=SimpleNamespace(free=64 * scratch.GIB))
        self.space.start()
        self.addCleanup(self.space.stop)

    def boundary(self):
        return scratch.redirect_boundary(self.home, "Projects/wt", self.alias, self.state, True)

    def test_open_files_survive_and_new_work_goes_to_scratch(self):
        with (self.root / "existing/file").open() as stream:
            inode = (self.root / "existing/file").stat().st_ino
            self.boundary()
            self.assertEqual(stream.read(), "unpublished work")
            self.assertEqual((self.root / "existing/file").stat().st_ino, inode)
        (self.root / "new").mkdir()
        (self.root / "new/file").write_text("bounded")
        self.assertEqual((self.alias / "home/Projects/wt/new/file").read_text(), "bounded")

    def test_idle_legacy_child_can_be_migrated_without_losing_its_path(self):
        self.boundary()
        result = scratch.migrate_one(self.home, "Projects/wt/existing", self.alias,
                                     [], self.state, lambda: [], True)
        self.assertEqual(result, "capped; verified old data removed")
        self.assertFalse((self.alias / "home/Projects/wt/existing").is_symlink())
        self.assertEqual((self.root / "existing/file").read_text(), "unpublished work")

    def test_legacy_child_referenced_through_original_alias_is_retained(self):
        self.boundary()
        result = scratch.migrate_one(self.home, "Projects/wt/existing", self.alias,
                                     [str(self.root / "existing/file")], self.state, lambda: [], True)
        self.assertEqual(result, "active source retained")

    def test_conflicting_destination_keeps_original_namespace(self):
        destination = self.alias / "home/Projects/wt/existing"
        destination.mkdir(parents=True)
        (destination / "file").write_text("different work")
        with self.assertRaisesRegex(RuntimeError, "different data"):
            self.boundary()
        self.assertFalse(self.root.is_symlink())
        self.assertEqual((self.root / "existing/file").read_text(), "unpublished work")


if __name__ == "__main__":
    unittest.main()
