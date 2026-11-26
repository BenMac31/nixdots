import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import call, patch


SPEC = importlib.util.spec_from_file_location(
    "install_agent_storage", Path(__file__).parents[1] / "scripts/install-agent-storage.py"
)
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)

RUNTIME = "/nix/store/" + "a" * 32 + "-agent-storage"
ZSH = "/nix/store/" + "b" * 32 + "-zsh-5.9.1/bin/zsh"
HOOK = (
    "  _agent_storage_shell_mode=-c\n"
    "  [[ -o login ]] && _agent_storage_shell_mode=-lc\n"
    f"  exec {RUNTIME}/bin/agent-storage command -- {ZSH} \\\n"
    '    "$_agent_storage_shell_mode" "$ZSH_EXECUTION_STRING" "$0" "$@"'
)


class NixEscaping(unittest.TestCase):
    def test_shell_interpolations_are_literal_in_nix(self):
        source = '${(@0)$(</proc/$$/cmdline)} "${args[@]:1}" $HOME\n'
        self.assertEqual(
            installer.nix_string(source),
            r'"\${(@0)$(</proc/$$/cmdline)} \"\${args[@]:1}\" $HOME\n"',
        )

    def test_backslash_cannot_undo_interpolation_escape(self):
        self.assertEqual(installer.nix_string('\\${shell}'), r'"\\\${shell}"')

    def test_bootstrap_roots_shell_and_cleanup_outputs(self):
        _, updated = installer.hook_replacement(HOOK, RUNTIME)
        expression = installer.build_expression(
            {"claude": "/nix/store/claude/bin/claude"},
            {"resolved": "/nix/store/zshenv"}, {"resolved": "/nix/store/cleanup"},
            RUNTIME, "/nix/store/bash-env", HOOK, updated,
        )
        self.assertIn('ln -s ${zshenv} "$out/share/agent-storage/zshenv"', expression)
        self.assertIn('ln -s ${cleanup} "$out/share/agent-storage/cleanup.service"', expression)
        self.assertIn('ln -s ${homeFiles} "$out/share/agent-storage/home-manager-files"', expression)
        self.assertIn('pkgs.runCommand "agent-storage-bootstrap-home-manager-files"', expression)
        self.assertIn('paths = [ runtime cfg.package ', expression)
        self.assertIn('ln -s ${zshenv} "$out/.zshenv"', expression)
        self.assertIn('ln -s ${cleanup} "$out/.config/systemd/user/agent-storage-cleanup.service"', expression)

    def test_installed_targets_retain_home_manager_ownership_pattern(self):
        bootstrap = '/nix/store/' + 'c' * 32 + '-agent-storage-bootstrap'
        files = '/nix/store/' + 'd' * 32 + '-agent-storage-bootstrap-home-manager-files'
        results = [{'outputs': {'out': path}} for path in (files, bootstrap)]
        with patch.object(installer, 'run_json', return_value=results), \
                patch.object(Path, 'read_text', return_value='{"migration_enabled": false}'):
            paths = installer.build('expression')
        self.assertEqual(paths['bootstrap'], bootstrap)
        self.assertEqual(paths['zshenv'], files + '/.zshenv')
        self.assertEqual(paths['cleanup'], files + '/.config/systemd/user/agent-storage-cleanup.service')
        for key in ('zshenv', 'cleanup'):
            self.assertRegex(paths[key], r'^/nix/store/[^/]+-home-manager-files/.+')


class ZshHook(unittest.TestCase):
    def test_exact_hook_preserves_shell_variables_and_pinned_zsh(self):
        content = 'before\n' + HOOK + '\nafter ${KEEP_ME}\n'
        old, new = installer.hook_replacement(content, RUNTIME)
        self.assertEqual(old, HOOK)
        self.assertEqual(new, (
            '  _agent_storage_argv=("${(@0)$(</proc/$$/cmdline)}")\n'
            '  _agent_storage_argv[-1]=()\n'
            f'  exec {RUNTIME}/bin/agent-storage command -- {ZSH} \\\n'
            '    "${_agent_storage_argv[@]:1}"'
        ))
        self.assertEqual(content.replace(old, new), 'before\n' + new + '\nafter ${KEEP_ME}\n')
        self.assertIn(r'\${(@0)', installer.nix_string(new))
        self.assertIn(r'\${_agent_storage_argv[@]:1}', installer.nix_string(new))

    def test_unexpected_hooks_are_refused(self):
        for content in (
            '', HOOK + '\n' + HOOK,
            HOOK.replace('[[ -o login ]]', '[[ -o interactive ]]'),
            HOOK.replace('"$@"', '$@'),
            HOOK + '\n_agent_storage_shell_mode=other',
        ):
            with self.subTest(content=content), self.assertRaises(ValueError):
                installer.hook_replacement(content, RUNTIME)

    def test_updated_hook_is_idempotent_and_additional_hooks_are_refused(self):
        _, updated = installer.hook_replacement(HOOK, RUNTIME)
        self.assertEqual(installer.hook_replacement(updated, RUNTIME), (updated, updated))
        for content in (
            updated + '\n' + updated,
            updated + '\n' + HOOK,
            updated + '\n_agent_storage_argv=other',
            updated.replace('_agent_storage_argv[-1]=()\n', ''),
            updated.replace('"${_agent_storage_argv[@]:1}"', '"$@"'),
        ):
            with self.subTest(content=content), self.assertRaises(ValueError):
                installer.hook_replacement(content, RUNTIME)

    def test_mismatched_runtime_is_refused(self):
        with self.assertRaises(ValueError):
            installer.hook_replacement(HOOK, RUNTIME + '-different')


class LixProfile(unittest.TestCase):
    path = '/nix/store/' + 'e' * 32 + '-agent-storage-bootstrap'

    def test_install_uses_supported_priority_and_store_path_arguments(self):
        with patch.object(installer.subprocess, 'run') as run:
            installer.install_entry(self.path, -20)
        run.assert_called_once_with(
            ['nix', 'profile', 'install', '--priority', '-20', self.path], check=True,
        )

    def test_manifest_key_is_verified_and_retained_for_derived_names(self):
        entry = {'storePaths': [self.path], 'priority': -20, 'active': True}
        for key in (installer.NAME, installer.NAME + '-1'):
            with self.subTest(key=key), patch.object(
                installer, 'run_json', return_value={'elements': {key: entry}},
            ):
                self.assertEqual(installer.verify_installed_entry(self.path, -20), dict(entry, name=key))

    def test_unrelated_name_and_ambiguous_bootstrap_entries_are_refused(self):
        owned = {'storePaths': [self.path], 'priority': -20}
        for entries in (
            {installer.NAME: {'storePaths': ['/nix/store/unrelated']}},
            {installer.NAME: owned, installer.NAME + '-1': owned},
        ):
            with self.subTest(entries=entries), patch.object(
                installer, 'run_json', return_value={'elements': entries},
            ), self.assertRaises(RuntimeError):
                installer.profile_entry()

    def test_unrelated_entries_do_not_match_and_wrong_priority_is_refused(self):
        with patch.object(installer, 'run_json', return_value={
            'elements': {'other': {'storePaths': ['/nix/store/unrelated']}},
        }):
            self.assertIsNone(installer.profile_entry())
        with patch.object(installer, 'run_json', return_value={
            'elements': {installer.NAME: {'storePaths': [self.path], 'priority': 5}},
        }), self.assertRaises(RuntimeError):
            installer.verify_installed_entry(self.path, -20)


class LoadedUnits(unittest.TestCase):
    def test_disabled_migration_is_idempotent_when_unit_was_removed(self):
        with patch.object(installer.subprocess, "check_output", return_value="not-found\n"), \
                patch.object(installer.subprocess, "run") as run:
            installer.disable_migration()
            run.assert_not_called()
        with patch.object(installer.subprocess, "check_output", return_value="loaded\n"), \
                patch.object(installer.subprocess, "run") as run:
            installer.disable_migration()
            self.assertEqual(run.call_args_list, [
                call(["systemctl", "--user", "stop", "agent-scratch-migrate.timer"], check=True),
                call(["systemctl", "--user", "disable", "agent-scratch-migrate.timer"], check=True)])

    def test_persistent_and_loaded_units_must_match_after_reload(self):
        with tempfile.TemporaryDirectory() as temp:
            paths = {}
            units = {"cleanup": "agent-storage-cleanup.service", **installer.UNITS}
            for key, name in units.items():
                path = Path(temp) / name
                path.write_text("ExecStart=/nix/store/current/bin/cleanup cleanup\n" if name.endswith(".service")
                                else "OnUnitInactiveSec=1min\n")
                paths[key] = str(path)
            def loaded(argv, **kwargs):
                return ("path=/nix/store/current/bin/cleanup ; argv[]=cleanup" if argv[3].endswith(".service")
                        else "{ OnUnitInactiveUSec=1min ; next_elapse=1min }")
            with patch.object(installer.subprocess, "check_output", side_effect=loaded):
                installer.verify_loaded(paths)
            with patch.object(installer.subprocess, "check_output", return_value="path=/nix/store/old/bin/cleanup"), \
                    self.assertRaisesRegex(RuntimeError, "loaded command differs"):
                installer.verify_loaded(paths)

    def test_all_storage_units_are_in_the_built_persistent_bundle(self):
        _, updated = installer.hook_replacement(HOOK, RUNTIME)
        expression = installer.build_expression({}, {"resolved": "/nix/store/zshenv"},
            {"resolved": "/nix/store/cleanup"}, RUNTIME, "/nix/store/bash-env", HOOK, updated,
            units=installer.UNITS)
        for name in installer.UNITS.values():
            self.assertIn('h.config.xdg.configFile."systemd/user/' + name + '".source', expression)
        self.assertIn('migration_enabled = cfg.migration.enable;', expression)


class Persistence(unittest.TestCase):
    def test_old_generation_fingerprints_survive_a_new_rollout_and_outputs_are_rooted(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            units = home / ".config/systemd/user"
            units.mkdir(parents=True)
            state = home / ".local/state/agent-storage-rollout"
            (state / "previous").mkdir(parents=True)
            keys = ("claude", "codex", "codex-api", "zshenv", "cleanup", *installer.UNITS)
            inputs = {key: {"path": str(home / key), "sha256": "0" * 64} for key in keys}
            (state / "previous/record.json").write_text(json.dumps({"status": "applied",
                "inputs": {key: {"sha256": "1" * 64} for key in keys}}))
            paths = {"bootstrap": "/nix/store/" + "a" * 32 + "-agent-storage-bootstrap",
                     "migration_enabled": False}
            with patch.object(installer.subprocess, "run") as run:
                installer.install_persistence(home, inputs, paths)
            manifest = json.loads((state / "desired.json").read_text())
            self.assertEqual(len(manifest["files"]), len(keys))
            for item in manifest["files"]:
                self.assertEqual(set(item["known_sha256"]), {"0" * 64, "1" * 64})
            self.assertEqual(run.call_args_list[0].args[0][0], "nix-store")
            self.assertIn("--indirect", run.call_args_list[0].args[0])
            self.assertTrue((units / "default.target.wants/agent-storage-restore.service").is_symlink())
            self.assertTrue((units / "timers.target.wants/agent-storage-restore.timer").is_symlink())


if __name__ == '__main__':
    unittest.main()
