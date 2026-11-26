import fcntl
import importlib.util
import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace


spec = importlib.util.spec_from_file_location(
    "pruner", Path(__file__).parents[1] / "modules/home-manager/term/gp-cache-prune.py"
)
pruner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pruner)


class RegistryPruneTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.origin = self.base / "origin.git"
        self.root = self.base / "registry-test"
        self.run_git("init", "--bare", "--initial-branch=main", str(self.origin))
        self.run_git("clone", str(self.origin), str(self.root))
        (self.root / "data").write_text("published\n")
        self.git("add", "data")
        self.git("commit", "-m", "published")
        self.git("push", "origin", "main")
        self.now = time.time() + pruner.AGE + 60

    def run_git(self, *args):
        return subprocess.run(
            ["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", *args],
            check=True, text=True, capture_output=True,
        )

    def git(self, *args):
        return self.run_git("-C", str(self.root), *args)

    def prune(self, paths=(), now=None):
        return pruner.prune(self.root, set(paths), self.now if now is None else now)

    def test_only_clean_published_unused_clone_is_removed(self):
        self.assertEqual(self.prune(), "removed")
        self.assertFalse(self.root.exists())
        self.assertTrue(self.root.with_name("registry-test.lock").exists())

    def test_recent_clone_is_preserved(self):
        self.assertEqual(self.prune(now=time.time()), "recently used")
        self.assertTrue(self.root.exists())

    def test_pressure_shortens_idle_window_without_weakening_source_checks(self):
        later = time.time() + 2 * 3600
        self.assertEqual(pruner.prune(self.root, set(), now=later, dry_run=True), "recently used")
        self.assertEqual(pruner.prune(self.root, set(), now=later, dry_run=True, age=3600),
                         "would remove")
        (self.root / "unique").write_text("unpublished work")
        self.assertEqual(pruner.prune(self.root, set(), now=later, age=3600), "local changes")
        self.assertTrue(self.root.exists())

    def test_pressure_retention_tracks_actual_free_space(self):
        for free_gib, expected in ((31, 3600), (32, pruner.AGE)):
            with self.subTest(free_gib=free_gib), patch.object(
                    pruner.shutil, "disk_usage", return_value=SimpleNamespace(free=free_gib * 1024**3)):
                self.assertEqual(pruner.retention_age(self.base, 32, 1), expected)
        self.assertEqual(pruner.retention_age(None, 32, 1), pruner.AGE)

    def test_discovery_covers_custom_namespaces_and_deduplicates_aliases(self):
        cache = self.base / "cache"
        custom = cache / "gp-task"
        custom.mkdir(parents=True)
        clone = custom / "registry-worker"
        clone.mkdir()
        alias = self.base / "cache-alias"
        alias.symlink_to(cache, target_is_directory=True)
        (cache / "unrelated").mkdir()
        (cache / "unrelated/registry-source").mkdir()
        self.assertEqual(list(pruner.discover([cache, alias])), [clone])

    def test_temporary_namespaces_are_discovered_without_searching_source_trees(self):
        temporary = self.base / "tmp"
        expected = []
        for namespace in ("task/gpcache", "another/gp-test", "third/gp"):
            clone = temporary / namespace / "registry-worker"
            clone.mkdir(parents=True)
            expected.append(clone)
        (temporary / "source/registry-keep").mkdir(parents=True)
        duplicate = temporary / "task/gpcache/registry-greencheetah"
        duplicate.mkdir()
        expected.append(duplicate)
        self.assertEqual(set(pruner.discover([], [temporary])), set(expected))

    def test_arbitrary_temporary_namespace_with_gp_lock_is_discovered_and_only_primary_is_protected(self):
        cache = self.base / "cache"
        primary = cache / "gp" / ("registry-" + pruner.getpass.getuser())
        primary.mkdir(parents=True)
        temporary = self.base / "tmp"
        namespace = temporary / "custom-review-name"
        duplicate = namespace / primary.name
        duplicate.mkdir(parents=True)
        duplicate.with_name(duplicate.name + ".lock").touch()
        unrelated = temporary / "source/registry-unrelated"
        unrelated.mkdir(parents=True)
        self.assertEqual(list(pruner.discover([cache], [temporary])), [duplicate])

    def test_critical_pressure_removes_only_verified_idle_mirrors(self):
        with patch.object(pruner.shutil, "disk_usage", return_value=SimpleNamespace(free=23 * 1024**3)):
            age = pruner.retention_age(self.base, 32, 1, 24)
        self.assertEqual(age, 0)
        self.assertEqual(pruner.prune(self.root, set(), dry_run=True, age=age), "would remove")
        with self.root.with_name("registry-test.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(pruner.prune(self.root, set(), age=age), "in use by gp")
        (self.root / "unique").write_text("unpublished work")
        self.assertEqual(pruner.prune(self.root, set(), age=age), "local changes")

    def test_critical_pressure_boundary_keeps_the_idle_window(self):
        with patch.object(pruner.shutil, "disk_usage", return_value=SimpleNamespace(free=24 * 1024**3)):
            self.assertEqual(pruner.retention_age(self.base, 32, 1, 24), 3600)

    def test_emergency_pass_stops_after_headroom_recovers(self):
        another = self.base / "registry-another"
        another.mkdir()
        readings = [SimpleNamespace(free=gib * 1024**3) for gib in (23, 23, 33)]
        with (patch.object(sys, "argv",
                           ["gp-cache-prune", "--pressure-path", str(self.base)]),
              patch.object(pruner.shutil, "disk_usage", side_effect=readings),
              patch.object(pruner, "active_paths", return_value=set()),
              patch.object(pruner, "discover", return_value=iter([self.root, another])),
              patch.object(pruner, "prune", side_effect=["would remove", "removed"]) as cleanup,
              contextlib.redirect_stdout(io.StringIO())):
            pruner.main()
        self.assertEqual(cleanup.call_count, 2)
        self.assertTrue(all(call.args[0] == self.root for call in cleanup.call_args_list))

    def test_untracked_data_is_preserved(self):
        (self.root / "unique").write_text("unpublished work\n")
        self.assertEqual(self.prune(), "local changes")
        self.assertTrue((self.root / "unique").exists())

    def test_unpublished_other_branch_is_preserved(self):
        self.git("checkout", "-b", "local")
        (self.root / "data").write_text("local commit\n")
        self.git("commit", "-am", "local")
        self.git("checkout", "main")
        self.assertEqual(self.prune(), "unpublished commits")
        self.assertTrue(self.root.exists())

    def test_stashed_changes_are_preserved(self):
        (self.root / "data").write_text("stashed\n")
        self.git("stash", "push")
        self.assertEqual(self.prune(), "has stashes")

    def test_recovery_ref_preserves_the_common_repository_and_bundle_bases(self):
        self.git("update-ref", "refs/archive/disk-budget/recovery", "HEAD")
        self.assertEqual(self.prune(), "has recovery refs")
        self.assertTrue(self.root.exists())

    def test_unpublished_commit_under_a_custom_ref_is_preserved(self):
        self.git("checkout", "--detach")
        self.git("commit", "--allow-empty", "-m", "private")
        self.git("update-ref", "refs/local/important", "HEAD")
        self.git("checkout", "main")
        self.assertEqual(self.prune(), "unpublished commits")
        self.assertTrue(self.root.exists())

    def test_gp_lifetime_lock_protects_active_command(self):
        with self.root.with_name("registry-test.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.prune(), "in use by gp")
        self.assertTrue(self.root.exists())

    def test_process_reference_protects_clone(self):
        self.assertEqual(self.prune([str(self.root / "data")]), "open by a process")

    def test_process_reference_protects_a_clone_beneath_a_symlinked_parent(self):
        alias = self.base / "alias"
        alias.symlink_to(self.base, target_is_directory=True)
        self.assertEqual(pruner.prune(alias / self.root.name, [str(self.root / "data")], self.now),
                         "open by a process")
        self.assertTrue(self.root.exists())

    def test_external_worktree_is_preserved(self):
        self.git("worktree", "add", "--detach", str(self.base / "worktree"))
        self.assertEqual(self.prune(), "has worktrees")
        self.assertTrue(self.root.exists())

    def test_interrupted_rebase_is_preserved(self):
        (self.root / ".git/rebase-merge").mkdir()
        self.assertEqual(self.prune(), "Git operation in progress")
        self.assertTrue(self.root.exists())


if __name__ == "__main__":
    unittest.main()
