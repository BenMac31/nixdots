import importlib.util
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


spec = importlib.util.spec_from_file_location(
    "cache", Path(__file__).parents[1] / "modules/home-manager/term/build-cache-prune.py")
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class BuildCacheCleanup(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        self.venv = self.project / ".venv"
        self.venv.mkdir()
        (self.venv / "pyvenv.cfg").write_text("home = /python\n")
        (self.venv / "lib").mkdir()
        (self.venv / "lib/module.py").write_text("reproducible dependency")
        (self.project / "proof.log").write_text("unique evidence")
        self.future = time.time() + 3 * 3600

    def prune(self, paths=()):
        return cache.prune(self.venv, paths, now=self.future)

    def test_removes_only_environment_and_preserves_evidence(self):
        self.assertEqual(self.prune(), "removed")
        self.assertTrue((self.project / "proof.log").exists())

    def test_recent_environment_is_preserved(self):
        self.assertEqual(cache.prune(self.venv, []), "recently changed")

    def test_open_project_preserves_environment(self):
        self.assertEqual(self.prune([str(self.project)]), "open project or cache")

    def test_open_dependency_preserves_environment(self):
        self.assertEqual(self.prune([str(self.venv / "lib/module.py")]), "open project or cache")

    def test_open_dependency_beneath_a_symlinked_parent_is_preserved(self):
        alias = self.project / "alias"
        alias.symlink_to(self.project, target_is_directory=True)
        self.assertEqual(cache.prune(alias / ".venv", [str(self.venv / "lib/module.py")],
                                     now=self.future), "open project or cache")
        self.assertTrue(self.venv.exists())

    def test_additional_data_is_preserved(self):
        (self.venv / "report.json").write_text("unique")
        self.assertEqual(self.prune(), "additional data in environment")

    def test_unverified_environment_is_preserved(self):
        (self.venv / "pyvenv.cfg").unlink()
        self.assertEqual(self.prune(), "unverified virtual environment")

    def test_tracked_dependencies_are_preserved(self):
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        subprocess.run(["git", "-C", str(self.project), "add", ".venv"], check=True)
        self.assertEqual(self.prune(), "contains tracked source")

    def test_node_modules_require_a_lockfile(self):
        modules = self.project / "node_modules"
        modules.mkdir()
        (self.project / "package.json").write_text("{}")
        self.assertEqual(cache.prune(modules, [], now=self.future), "no dependency lockfile")
        (self.project / "package-lock.json").write_text("{}")
        self.assertEqual(cache.prune(modules, [], now=self.future), "removed")

    def test_symlink_is_preserved(self):
        linked = self.project / "elsewhere/.venv"
        linked.parent.mkdir()
        linked.symlink_to(self.venv)
        self.assertEqual(cache.prune(linked, [], now=self.future), "not a disposable directory")

    def test_only_verified_stopped_throwaway_databases_are_removed(self):
        cluster = self.project / "backtest-pg-data"
        cluster.mkdir()
        (cluster / "PG_VERSION").write_text("18")
        (cluster / "base").mkdir()
        (cluster / "global").mkdir()
        recipe = self.project / "pg_backtest.sh"
        recipe.write_text('data="$RUNNER_TEMP/backtest-pg-data"\ninitdb pg_ctl trap fsync=off\n')
        self.assertEqual(cache.prune(cluster, [], now=self.future), "removed")
        self.assertTrue(recipe.exists())
        self.assertTrue((self.project / "proof.log").exists())

    def test_database_pid_marker_prevents_cleanup(self):
        cluster = self.project / "backtest-pg-data"
        cluster.mkdir()
        (cluster / "PG_VERSION").write_text("18")
        (cluster / "base").mkdir()
        (cluster / "global").mkdir()
        (cluster / "postmaster.pid").write_text("1234")
        (self.project / "pg_backtest.sh").write_text('data="$RUNNER_TEMP/backtest-pg-data"\ninitdb pg_ctl trap fsync=off\n')
        self.assertEqual(cache.prune(cluster, [], now=self.future), "database has a PID marker")

    def test_unknown_database_data_is_preserved(self):
        cluster = self.project / "backtest-pg-data"
        cluster.mkdir()
        self.assertEqual(cache.prune(cluster, [], now=self.future), "unverified test database")


if __name__ == "__main__":
    unittest.main()
