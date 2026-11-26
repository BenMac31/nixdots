import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "prune", Path(__file__).parents[1] / "modules/home-manager/term/worktree-prune.py")
prune = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prune)


class WorktreeRetirement(unittest.TestCase):
    def setUp(self):
        git_config = patch.dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null")
        git_config.start()
        self.addCleanup(git_config.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.tree = self.root / "tree"
        self.run_git("init", "-q", str(self.repo))
        self.run_git("-C", str(self.repo), "config", "user.name", "Test")
        self.run_git("-C", str(self.repo), "config", "user.email", "test@example.invalid")
        (self.repo / "source").write_text("published\n")
        self.git("add", "source")
        self.git("commit", "-qm", "published")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("worktree", "add", "-qb", "task", str(self.tree))
        self.future = time.time() + 7 * 3600
        space = patch.object(prune.os, "statvfs", return_value=SimpleNamespace(
            f_bavail=128 * 1024**3, f_frsize=1))
        space.start()
        self.addCleanup(space.stop)

    def run_git(self, *args):
        return subprocess.check_output(["git", *args], stderr=subprocess.DEVNULL, text=True).strip()

    def git(self, *args):
        return self.run_git("-C", str(self.repo), *args)

    def retire(self, paths=()):
        return prune.retire(self.tree, paths, 6, now=self.future)[0]

    def test_removes_published_tree_but_keeps_branch_and_repository(self):
        self.assertEqual(self.retire(), "removed")
        self.assertFalse(self.tree.exists())
        self.assertEqual(self.git("rev-parse", "task"), self.git("rev-parse", "HEAD"))
        self.assertTrue((self.repo / "source").exists())

    def test_preserves_untracked_files(self):
        (self.tree / "evidence").write_text("unique result")
        self.assertEqual(self.retire(), "local changes")

    def test_preserves_modified_tracked_files(self):
        (self.tree / "source").write_text("uncommitted")
        self.assertEqual(self.retire(), "local changes")

    def test_preserves_ignored_evidence(self):
        (self.repo / ".git/info/exclude").write_text("*.log\n")
        (self.tree / "proof.log").write_text("unique evidence")
        self.assertEqual(self.retire(), "ignored evidence or other data")

    def test_verified_archive_preserves_ignored_evidence_after_retirement(self):
        (self.repo / ".git/info/exclude").write_text("*.log\n")
        (self.tree / "proof.log").write_text("unique evidence\n")
        archives = self.root / "archives"
        reason, record = prune.retire(self.tree, [], 6, now=self.future, archive_dir=archives)
        self.assertEqual(reason, "removed")
        self.assertFalse(self.tree.exists())
        restored = subprocess.check_output(
            ["tar", "-xOf", record["archive"], "--use-compress-program=zstd -q -d", "proof.log"])
        self.assertEqual(restored, b"unique evidence\n")

    def test_archive_failure_preserves_the_worktree(self):
        (self.repo / ".git/info/exclude").write_text("*.log\n")
        (self.tree / "proof.log").write_text("unique evidence")
        with patch.object(prune, "archive_ignored", side_effect=OSError("out of space")):
            with self.assertRaises(OSError):
                prune.retire(self.tree, [], 6, now=self.future, archive_dir=self.root / "archives")
        self.assertTrue((self.tree / "proof.log").exists())

    def test_special_files_cannot_be_silently_omitted_from_a_requested_archive(self):
        os.mkfifo(self.tree / "proof.log")
        with self.assertRaisesRegex(RuntimeError, "special files"):
            prune.archive_ignored(self.tree, {"ignored": ["proof.log"]}, self.root / "archives")
        self.assertTrue((self.tree / "proof.log").exists())

    def test_live_unix_socket_protects_a_worktree_without_cwd_or_regular_file_references(self):
        endpoint = self.tree / "active.sock"
        code = ("import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind("
                + json.dumps(str(endpoint)) + "); s.listen(); print('ready',flush=True); sys.stdin.read()")
        process = subprocess.Popen([sys.executable, "-c", code], cwd="/", stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(process.stdout.readline().strip(), "ready")
            paths = prune.active_paths()
            self.assertIn(str(endpoint), paths)
            self.assertEqual(self.retire(paths), "open by a process")
        finally:
            process.communicate("")

    def test_repeated_archiving_reuses_the_verified_archive(self):
        (self.repo / ".git/info/exclude").write_text("*.log\n")
        (self.tree / "proof.log").write_text("unique evidence")
        _, record = prune.inspect(self.tree, [], 6, self.future)
        archives = self.root / "archives"
        prune.archive_ignored(self.tree, record, archives)
        first = record["archive"]
        prune.archive_ignored(self.tree, record, archives)
        self.assertEqual(record["archive"], first)
        self.assertEqual(len(list(archives.glob("*.tar.zst"))), 1)

    def test_one_off_archive_restores_staged_unstaged_untracked_and_ignored_work(self):
        (self.repo / ".git/info/exclude").write_text("*.log\n")
        (self.tree / "source").write_text("staged version\n")
        self.run_git("-C", str(self.tree), "add", "source")
        (self.tree / "source").write_text("working version\n")
        (self.tree / "recipe.py").write_text("unique recipe\n")
        (self.tree / "proof.log").write_text("unique evidence\n")
        reason, record = prune.retire(self.tree, [], 6, now=self.future,
                                     archive_dir=self.root / "archives", archive_local_changes=True)
        self.assertEqual(reason, "removed")
        recovery = Path(record["recovery"])
        restored = self.root / "restored"
        self.git("worktree", "add", "--detach", str(restored), record["head"])
        self.run_git("-C", str(restored), "apply", "--index", str(recovery / "staged.patch"))
        self.run_git("-C", str(restored), "apply", str(recovery / "unstaged.patch"))
        subprocess.run(["tar", "-xf", record["archive"], "--use-compress-program=zstd -q -d",
                        "-C", str(restored)], check=True)
        self.assertEqual((restored / "source").read_text(), "working version\n")
        self.assertEqual(self.run_git("-C", str(restored), "show", ":source"), "staged version")
        self.assertEqual((restored / "recipe.py").read_text(), "unique recipe\n")
        self.assertEqual((restored / "proof.log").read_text(), "unique evidence\n")

    def test_one_off_archive_still_preserves_unpublished_commits_in_place(self):
        self.run_git("-C", str(self.tree), "commit", "--allow-empty", "-qm", "private")
        (self.tree / "source").write_text("uncommitted too")
        reason, _ = prune.retire(self.tree, [], 6, now=self.future,
                                archive_dir=self.root / "archives", archive_local_changes=True)
        self.assertEqual(reason, "unpublished commits")
        self.assertTrue(self.tree.exists())

    def test_explicit_unpublished_archive_restores_a_detached_commit(self):
        self.run_git("-C", str(self.tree), "checkout", "--detach", "-q")
        (self.tree / "source").write_text("unpublished committed work\n")
        self.run_git("-C", str(self.tree), "commit", "-qam", "private")
        head = self.run_git("-C", str(self.tree), "rev-parse", "HEAD")
        reason, record = prune.retire(self.tree, [], 24, now=self.future + 24 * 3600,
                                     archive_dir=self.root / "archives", archive_unpublished=True)
        self.assertEqual(reason, "removed")
        self.assertEqual(self.git("rev-parse", record["recovery_ref"]), head)
        restored = self.root / "restored"
        self.run_git("init", "-q", str(restored))
        self.run_git("-C", str(restored), "fetch", str(self.repo), "refs/remotes/origin/main")
        self.run_git("-C", str(restored), "fetch", record["commit_bundle"], "HEAD")
        self.assertEqual(self.run_git("-C", str(restored), "show", "FETCH_HEAD:source"),
                         "unpublished committed work")

    def test_unpublished_bundle_failure_keeps_the_source(self):
        self.run_git("-C", str(self.tree), "commit", "--allow-empty", "-qm", "private")
        with patch.object(prune, "archive_head", side_effect=OSError("archive failed")):
            with self.assertRaises(OSError):
                prune.retire(self.tree, [], 24, now=self.future + 24 * 3600,
                             archive_dir=self.root / "archives", archive_unpublished=True)
        self.assertTrue(self.tree.exists())

    def test_unpublished_lfs_payloads_are_retained_in_place(self):
        (self.tree / "pointer").write_text(
            "version https://git-lfs.github.com/spec/v1\noid sha256:" + "0" * 64 + "\nsize 12\n")
        self.run_git("-C", str(self.tree), "add", "pointer")
        self.run_git("-C", str(self.tree), "commit", "-qm", "private LFS payload")
        with self.assertRaisesRegex(RuntimeError, "unpublished LFS"):
            prune.retire(self.tree, [], 24, now=self.future + 24 * 3600,
                         archive_dir=self.root / "archives", archive_unpublished=True)
        self.assertTrue(self.tree.exists())

    def test_process_arriving_during_commit_backup_keeps_the_source(self):
        self.run_git("-C", str(self.tree), "commit", "--allow-empty", "-qm", "private")
        with patch.object(prune, "active_paths", return_value={str(self.tree)}):
            reason, record = prune.retire(self.tree, [], 24, now=self.future + 24 * 3600,
                                         archive_dir=self.root / "archives", archive_unpublished=True)
        self.assertEqual(reason, "changed during archiving")
        self.assertTrue(self.tree.exists())
        self.assertTrue(Path(record["commit_bundle"]).exists())

    def test_process_arriving_during_archiving_preserves_original_tree(self):
        (self.tree / "source").write_text("local work")
        with patch.object(prune, "active_paths", return_value={str(self.tree)}):
            reason, _ = prune.retire(self.tree, [], 6, now=self.future,
                                    archive_dir=self.root / "archives", archive_local_changes=True)
        self.assertEqual(reason, "changed during archiving")
        self.assertEqual((self.tree / "source").read_text(), "local work")

    def test_modified_lfs_content_stays_in_place(self):
        self.git("config", "filter.lfs.process", "")
        self.git("config", "filter.lfs.clean", "cat")
        self.git("config", "filter.lfs.required", "false")
        (self.tree / ".gitattributes").write_text("source filter=lfs\n")
        (self.tree / "source").write_text("modified")
        with self.assertRaisesRegex(RuntimeError, "LFS"):
            prune.retire(self.tree, [], 6, now=self.future,
                         archive_dir=self.root / "archives", archive_local_changes=True)
        self.assertTrue(self.tree.exists())

    def test_new_lfs_attributes_do_not_pin_byte_identical_published_files(self):
        self.git("config", "filter.lfs.clean", "printf filtered")
        self.git("config", "filter.lfs.required", "false")
        (self.tree / ".gitattributes").write_text("source filter=lfs\n")
        (self.tree / "source").write_text("published\n")
        reason, record = prune.retire(self.tree, [], 6, now=self.future,
                                     archive_dir=self.root / "archives", archive_local_changes=True)
        self.assertEqual(reason, "removed")
        self.assertEqual(record["filter_only_paths"], ["source"])
        recovery = Path(record["recovery"])
        self.assertEqual((recovery / "staged.patch").read_bytes(), b"")
        self.assertEqual((recovery / "unstaged.patch").read_bytes(), b"")
        self.assertEqual(self.git("show", "HEAD:source"), "published")
        self.assertIn(".gitattributes", subprocess.check_output(
            ["tar", "--zstd", "-tf", record["archive"]], text=True))

    def test_lfs_staged_changes_remain_in_place_even_with_identical_working_file(self):
        self.git("config", "filter.lfs.clean", "printf filtered")
        self.git("config", "filter.lfs.required", "false")
        (self.tree / ".gitattributes").write_text("source filter=lfs\n")
        (self.tree / "source").write_text("published\n")
        self.run_git("-C", str(self.tree), "add", "--renormalize", "source")
        with self.assertRaisesRegex(RuntimeError, "LFS"):
            prune.retire(self.tree, [], 6, now=self.future,
                         archive_dir=self.root / "archives", archive_local_changes=True)
        self.assertTrue(self.tree.exists())

    def test_lfs_mode_changes_remain_in_place(self):
        self.git("config", "filter.lfs.clean", "printf filtered")
        self.git("config", "filter.lfs.required", "false")
        (self.tree / ".gitattributes").write_text("source filter=lfs\n")
        (self.tree / "source").chmod(0o755)
        with self.assertRaisesRegex(RuntimeError, "LFS"):
            prune.retire(self.tree, [], 6, now=self.future,
                         archive_dir=self.root / "archives", archive_local_changes=True)
        self.assertTrue(self.tree.exists())

    def test_one_off_archive_cannot_exhaust_the_disk(self):
        (self.tree / "source").write_text("local work")
        with patch.object(prune.os, "statvfs", return_value=SimpleNamespace(f_bavail=1024, f_frsize=1)):
            with self.assertRaisesRegex(RuntimeError, "headroom"):
                prune.retire(self.tree, [], 6, now=self.future,
                             archive_dir=self.root / "archives", archive_local_changes=True)
        self.assertEqual((self.tree / "source").read_text(), "local work")

    def test_allows_only_recognized_build_cache_directories(self):
        (self.repo / ".git/info/exclude").write_text("target/\n")
        (self.tree / "target").mkdir()
        (self.tree / "target/compiler-output").write_text("reproducible")
        self.assertEqual(self.retire(), "removed")

    def test_preserves_unpublished_commits(self):
        self.run_git("-C", str(self.tree), "commit", "--allow-empty", "-qm", "not published")
        self.assertEqual(self.retire(), "unpublished commits")

    def test_preserves_process_references(self):
        self.assertEqual(self.retire([str(self.tree / "source")]), "open by a process")

    def test_process_references_protect_paths_beneath_a_symlinked_parent(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        reason, _ = prune.inspect(alias / "tree", [str(self.tree / "source")], 6, now=self.future)
        self.assertEqual(reason, "open by a process")

    def test_preserves_locked_worktrees(self):
        self.git("worktree", "lock", str(self.tree))
        self.assertEqual(self.retire(), "locked")

    def test_preserves_recent_worktrees(self):
        self.assertEqual(prune.retire(self.tree, [], 6)[0], "recently used")

    def test_never_removes_primary_checkout(self):
        self.assertEqual(prune.retire(self.repo, [], 6, now=self.future)[0], "not a linked worktree")

    def test_preserves_interrupted_git_operations(self):
        gd = Path(prune.git(self.tree, "rev-parse", "--absolute-git-dir"))
        (gd / "MERGE_HEAD").write_text(self.git("rev-parse", "HEAD"))
        self.assertEqual(self.retire(), "Git operation in progress")

    def test_dry_run_leaves_tree_present(self):
        self.assertEqual(prune.retire(self.tree, [], 6, True, self.future)[0], "would remove")
        self.assertTrue(self.tree.exists())

    def test_git_failure_never_forces_removal(self):
        self.git("config", "alias.worktree", "!exit 1")
        # Initialized submodules make native worktree removal refuse the tree.
        sub = self.root / "sub"
        self.run_git("clone", "-q", str(self.repo), str(sub))
        self.run_git("-c", "protocol.file.allow=always", "-C", str(self.tree),
                     "submodule", "add", "-q", str(sub), "nested")
        self.run_git("-C", str(self.tree), "commit", "-qam", "submodule")
        self.git("update-ref", "refs/remotes/origin/main", "task")
        with self.assertRaises(subprocess.CalledProcessError):
            self.retire()
        self.assertTrue((self.tree / "nested/source").exists())


if __name__ == "__main__":
    unittest.main()
