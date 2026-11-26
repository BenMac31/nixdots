#!/usr/bin/env python3
"""Build or install only the agent-storage runtime, wrappers and shell hooks."""

import argparse
import fcntl
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


NAME = "agent-storage-bootstrap"
REPO = Path(__file__).resolve().parents[1]
STORE = r"/nix/store/[a-z0-9]{32}-"
RUNTIME = re.compile(STORE + r"agent-storage(?=/bin/agent-storage)")
BASH_ENV = re.compile(r"^export BASH_ENV=(" + STORE + r"agent-storage-bash-env)$", re.M)
HOOK = re.compile(
    r'^  _agent_storage_shell_mode=-c\n'
    r'  \[\[ -o login \]\] && _agent_storage_shell_mode=-lc\n'
    r'  exec (?P<runtime>' + STORE + r'agent-storage)/bin/agent-storage command -- '
    r'(?P<zsh>' + STORE + r'zsh-[^/\s]+/bin/zsh) \\\n'
    r'    "\$_agent_storage_shell_mode" "\$ZSH_EXECUTION_STRING" "\$0" "\$@"$', re.M
)
ARRAY_HOOK = re.compile(
    '^' + re.escape('  _agent_storage_argv=("${(@0)$(</proc/$$/cmdline)}")\n'
                     '  _agent_storage_argv[-1]=()\n  exec ')
    + r'(?P<runtime>' + STORE + r'agent-storage)/bin/agent-storage command -- '
    + r'(?P<zsh>' + STORE + r'zsh-[^/\s]+/bin/zsh)'
    + re.escape(' \\\n    "${_agent_storage_argv[@]:1}"') + '$', re.M
)
UNITS = {
    "registry_service": "gp-cache-prune.service",
    "registry_timer": "gp-cache-prune.timer",
    "cleanup_timer": "agent-storage-cleanup.timer",
}


def nix_string(value):
    """A double-quoted Nix literal; JSON alone permits Nix interpolation."""
    return json.dumps(value, ensure_ascii=False).replace("${", r"\${")


def hook_replacement(content, old_runtime):
    original = list(HOOK.finditer(content))
    updated = list(ARRAY_HOOK.finditer(content))
    matches = original + updated
    if len(matches) != 1 or matches[0]["runtime"] != old_runtime:
        raise ValueError("unexpected zsh command hook; expected exactly one recognized hook")
    if (content.count("_agent_storage_shell_mode") != (3 if original else 0)
            or content.count("_agent_storage_argv") != (3 if updated else 0)):
        raise ValueError("unexpected additional zsh command hook")
    match = matches[0]
    if updated:
        return match[0], match[0]
    replacement = (
        '  _agent_storage_argv=("${(@0)$(</proc/$$/cmdline)}")\n'
        '  _agent_storage_argv[-1]=()\n'
        f'  exec {old_runtime}/bin/agent-storage command -- {match["zsh"]} \\\n'
        '    "${_agent_storage_argv[@]:1}"'
    )
    return match[0], replacement


def snapshot(path, require_symlink=False):
    if require_symlink and not path.is_symlink():
        raise ValueError(f"expected a symlink: {path}")
    resolved = path.resolve(strict=True)
    if not str(resolved).startswith("/nix/store/"):
        raise ValueError(f"input is outside the Nix store: {path}")
    content = path.read_bytes()
    return {
        "path": str(path), "resolved": str(resolved),
        "target": os.readlink(path) if path.is_symlink() else None,
        "sha256": hashlib.sha256(content).hexdigest(),
    }, content.decode("utf-8")


def collect_inputs(home):
    inputs, wrappers = {}, {}
    runtimes, bash_envs = set(), set()
    for name in ("claude", "codex", "codex-api"):
        item, content = snapshot(home / ".nix-profile/bin" / name)
        found_runtime = set(RUNTIME.findall(content))
        found_bash = BASH_ENV.findall(content)
        if len(found_runtime) != 1 or len(found_bash) != 1:
            raise ValueError(f"unexpected runtime or BASH_ENV in {name}")
        runtimes.update(found_runtime)
        bash_envs.update(found_bash)
        inputs[name] = item
        wrappers[name] = item["resolved"]
    if len(runtimes) != 1 or len(bash_envs) != 1:
        raise ValueError("live wrappers disagree on runtime or BASH_ENV")
    old_runtime, old_bash = runtimes.pop(), bash_envs.pop()
    zsh, zsh_content = snapshot(home / ".zshenv", require_symlink=True)
    unit, unit_content = snapshot(
        home / ".config/systemd/user/agent-storage-cleanup.service", require_symlink=True
    )
    if set(RUNTIME.findall(zsh_content)) != {old_runtime}:
        raise ValueError("zsh runtime differs from live wrappers")
    if set(RUNTIME.findall(unit_content)) != {old_runtime}:
        raise ValueError("cleanup runtime differs from live wrappers")
    old_hook, new_hook = hook_replacement(zsh_content, old_runtime)
    inputs.update(zshenv=zsh, cleanup=unit)
    for key, name in UNITS.items():
        inputs[key], _ = snapshot(home / ".config/systemd/user" / name, require_symlink=True)
    return inputs, build_expression(wrappers, zsh, unit, old_runtime, old_bash, old_hook, new_hook,
                                    units=UNITS)


def build_expression(wrappers, zsh, unit, old_runtime, old_bash, old_hook, new_hook, units=None):
    def read(path):
        return f"(builtins.readFile (builtins.toPath {nix_string(path)}))"

    wrapper_exprs = []
    unit_links = "\n".join(
        '    ln -s ${h.config.xdg.configFile.' + nix_string("systemd/user/" + name)
        + '.source} "$out/.config/systemd/user/' + name + '"'
        for name in (units or {}).values()
    )
    for name, path in wrappers.items():
        wrapper_exprs.append(
            f"(pkgs.writeScriptBin {nix_string(name)} (builtins.replaceStrings "
            f"[ {nix_string(old_runtime)} {nix_string(old_bash)} ] "
            f"[ runtime.outPath (toString cfg.bashInit) ] {read(path)}))"
        )
    # Replace the whole validated hook first; the second pass updates every runtime reference.
    return f"""let
  h = (builtins.getFlake {nix_string('git+file://' + str(REPO))}).homeConfigurations.nixUltra;
  pkgs = h.pkgs;
  cfg = h.config.services.agentScratch;
  runtime = cfg.runtimePackage;
  restore = pkgs.writeText "restore-agent-storage.py" {read(str(REPO / 'scripts/restore-agent-storage.py'))};
  bootstrap = pkgs.symlinkJoin {{
    name = {nix_string(NAME)};
    paths = [ runtime cfg.package {' '.join(wrapper_exprs)} ];
    postBuild = ''
      mkdir -p "$out/share/agent-storage"
      ln -s ${{homeFiles}} "$out/share/agent-storage/home-manager-files"
      ln -s ${{zshenv}} "$out/share/agent-storage/zshenv"
      ln -s ${{cleanup}} "$out/share/agent-storage/cleanup.service"
      ln -s ${{restore}} "$out/share/agent-storage/restore.py"
      cat > "$out/share/agent-storage/agent-storage-restore.service" <<EOF
[Unit]
Description=Restore the verified agent-storage rollout after legacy Home Manager activation
Before=agent-storage-cleanup.service gp-cache-prune.service agent-scratch-migrate.service
[Service]
Type=oneshot
ExecStart=${{pkgs.python3}}/bin/python3 $out/share/agent-storage/restore.py --manifest "{Path.home() / '.local/state/agent-storage-rollout/desired.json'}" --nix ${{pkgs.lix}}/bin/nix --systemctl ${{pkgs.systemd}}/bin/systemctl
TimeoutStartSec=2min
[Install]
WantedBy=default.target
EOF
      cat > "$out/share/agent-storage/agent-storage-restore.timer" <<EOF
[Unit]
Description=Check agent-storage deployment persistence
[Timer]
OnBootSec=10s
OnUnitInactiveSec=1min
Unit=agent-storage-restore.service
[Install]
WantedBy=timers.target
EOF
    '';
  }};
  zshenv = pkgs.writeText "{NAME}-zshenv" (builtins.replaceStrings
    [ {nix_string(old_runtime)} ] [ runtime.outPath ]
    (builtins.replaceStrings [ {nix_string(old_hook)} ] [ {nix_string(new_hook)} ]
      {read(zsh['resolved'])}));
  cleanup = pkgs.writeText "{NAME}-cleanup.service" (builtins.replaceStrings
    [ {nix_string(old_runtime)} ] [ runtime.outPath ] {read(unit['resolved'])});
  policy = pkgs.writeText "agent-storage-policy.json" (builtins.toJSON {{
    migration_enabled = cfg.migration.enable;
  }});
  homeFiles = pkgs.runCommand "{NAME}-home-manager-files" {{ }} ''
    mkdir -p "$out/.config/systemd/user"
    ln -s ${{zshenv}} "$out/.zshenv"
    ln -s ${{cleanup}} "$out/.config/systemd/user/agent-storage-cleanup.service"
    ln -s ${{policy}} "$out/policy.json"
{unit_links}
  '';
in [ bootstrap homeFiles ]
"""


def run_json(command):
    return json.loads(subprocess.check_output(command, text=True))


def build(expression):
    results = run_json([
        "nix", "build", "--impure", "--expr", expression,
        "--json", "--no-link", "--no-write-lock-file",
    ])
    names = {NAME: "bootstrap", NAME + "-home-manager-files": "home_files"}
    paths = {}
    for result in results:
        output = result["outputs"]["out"]
        name = Path(output).name.split("-", 1)[1]
        if name not in names or names[name] in paths:
            raise ValueError(f"unexpected or duplicate build output: {output}")
        paths[names[name]] = output
    if set(paths) != set(names.values()):
        raise ValueError("missing build outputs")
    paths["zshenv"] = paths["home_files"] + "/.zshenv"
    paths["cleanup"] = paths["home_files"] + "/.config/systemd/user/agent-storage-cleanup.service"
    for key, name in UNITS.items():
        paths[key] = paths["home_files"] + "/.config/systemd/user/" + name
    policy = json.loads((Path(paths["home_files"]) / "policy.json").read_text())
    if type(policy.get("migration_enabled")) is not bool:
        raise ValueError("invalid migration policy")
    paths["migration_enabled"] = policy["migration_enabled"]
    return paths


def verify_inputs(inputs):
    for item in inputs.values():
        current, _ = snapshot(Path(item["path"]))
        if current != item:
            raise RuntimeError(f"live input changed during build: {item['path']}; rebuild before applying")


def profile_entry():
    entries = run_json(["nix", "profile", "list", "--json"])["elements"]
    matches = []
    for key, entry in entries.items():
        store_paths = entry.get("storePaths", [])
        owned = (len(store_paths) == 1
                 and re.fullmatch(STORE + re.escape(NAME), store_paths[0]) is not None)
        if key == NAME and not owned:
            raise RuntimeError("bootstrap profile name is occupied by an unrelated entry")
        if owned:
            matches.append(dict(entry, name=key))
    if len(matches) > 1:
        raise RuntimeError("multiple bootstrap profile entries; refusing ambiguous removal")
    return matches[0] if matches else None


def install_entry(path, priority):
    subprocess.run([
        "nix", "profile", "install", "--priority", str(priority), path,
    ], check=True)


def verify_installed_entry(path, priority):
    entry = profile_entry()
    if (entry is None or entry.get("storePaths") != [path]
            or entry.get("priority") != priority or not entry.get("active", True)):
        raise RuntimeError("installed bootstrap profile entry does not match requested path and priority")
    return entry


def replace_symlink(path, target):
    # A temporary link in the same directory makes the visible replacement atomic.
    temporary = Path(tempfile.mkdtemp(prefix=".agent-storage-", dir=path.parent))
    try:
        link = temporary / "link"
        link.symlink_to(target)
        os.replace(link, path)
    finally:
        temporary.rmdir()


def write_record(directory, record):
    path = directory / "record.json"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(record, stream, indent=2)
        stream.write("\n")


def verify_loaded(paths):
    for key, unit in {"cleanup": "agent-storage-cleanup.service", **UNITS}.items():
        installed = Path(paths[key]).read_text()
        if unit.endswith(".service"):
            expected = re.search(r"^ExecStart=(\S+)", installed, re.M).group(1)
            actual = subprocess.check_output(
                ["systemctl", "--user", "show", unit, "-p", "ExecStart", "--value"], text=True)
            if expected not in actual:
                raise RuntimeError(f"loaded command differs from persistent unit: {unit}")
        else:
            expected = re.search(r"^OnUnitInactiveSec=(\S+)", installed, re.M).group(1)
            actual = subprocess.check_output(
                ["systemctl", "--user", "show", unit, "-p", "TimersMonotonic", "--value"], text=True)
            if expected == "1min" and "OnUnitInactiveUSec=1min" not in actual:
                raise RuntimeError(f"loaded timer differs from persistent unit: {unit}")


def disable_migration():
    unit = "agent-scratch-migrate.timer"
    state = subprocess.check_output(
        ["systemctl", "--user", "show", unit, "-p", "LoadState", "--value"], text=True).strip()
    if state != "not-found":
        subprocess.run(["systemctl", "--user", "stop", unit], check=True)
        subprocess.run(["systemctl", "--user", "disable", unit], check=True)


def apply(home, inputs, paths):
    previous = profile_entry()
    if previous and (len(previous.get("storePaths", [])) != 1 or not previous.get("active", True)):
        raise ValueError("existing bootstrap entry cannot be restored as a single active store path")
    verify_inputs(inputs)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    directory = home / ".local/state/agent-storage-rollout" / stamp
    directory.mkdir(mode=0o700, parents=True)
    record = {"inputs": inputs, "built": paths, "previous_bootstrap": previous, "status": "prepared"}
    write_record(directory, record)
    changed_links = []
    profile_changed = False
    try:
        # Check again immediately before the first live write.
        verify_inputs(inputs)
        if profile_entry() != previous:
            raise RuntimeError("bootstrap profile entry changed before apply")
        if previous:
            subprocess.run(["nix", "profile", "remove", previous["storePaths"][0]], check=True)
            profile_changed = True
        install_entry(paths["bootstrap"], -20)
        profile_changed = True
        record["installed_bootstrap"] = verify_installed_entry(paths["bootstrap"], -20)
        for key in ("zshenv", "cleanup", *UNITS):
            item = inputs[key]
            current, _ = snapshot(Path(item["path"]))
            if current != item:
                raise RuntimeError(f"live input changed before replacement: {item['path']}")
            replace_symlink(Path(item["path"]), paths[key])
            changed_links.append(key)
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        verify_loaded(paths)
        if not paths["migration_enabled"]:
            disable_migration()
        subprocess.run(["systemctl", "--user", "restart", "agent-storage-cleanup.timer", "gp-cache-prune.timer"], check=True)
        # A second reload catches fixes that exist only in the manager's cache.
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        verify_loaded(paths)
        record["status"] = "applied"
        write_record(directory, record)
    except BaseException as error:
        record.update(status="failed", error=str(error), error_type=type(error).__name__,
                      changed_links=changed_links, profile_changed=profile_changed)
        write_record(directory, record)
        try:
            for key in reversed(changed_links):
                replace_symlink(Path(inputs[key]["path"]), inputs[key]["target"])
            if profile_changed:
                current = profile_entry()
                if current:
                    subprocess.run(["nix", "profile", "remove", current["storePaths"][0]], check=True)
                if previous:
                    install_entry(previous["storePaths"][0], previous.get("priority", 5))
            subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
            record["rollback"] = "restored prior persistent links and profile"
        except BaseException as rollback_error:
            record["rollback_error"] = str(rollback_error)
        write_record(directory, record)
        raise RuntimeError(f"apply failed: {error}; manual recovery record: "
                           f"{directory / 'record.json'}") from error
    return str(directory / "record.json")


def install_persistence(home, inputs, paths):
    state = home / ".local/state/agent-storage-rollout"
    # This independent root survives removal of the user-profile entry at boot.
    subprocess.run(["nix-store", "--realise", paths["bootstrap"], "--add-root",
                    str(state / "gcroot"), "--indirect"], check=True, stdout=subprocess.DEVNULL)
    known = {key: {item["sha256"]} for key, item in inputs.items()}
    for path in state.glob("*/record.json"):
        try:
            record = json.loads(path.read_text())
            if record.get("status") != "applied":
                continue
            for key, item in record["inputs"].items():
                known.setdefault(key, set()).add(item["sha256"])
        except (OSError, ValueError, KeyError):
            continue
    files = []
    for key in ("claude", "codex", "codex-api", "zshenv", "cleanup", *UNITS):
        kind = "profile" if key in ("claude", "codex", "codex-api") else "link"
        relative = ".zshenv" if key == "zshenv" else ".config/systemd/user/" + (
            "agent-storage-cleanup.service" if key == "cleanup" else UNITS.get(key, ""))
        source = (paths["bootstrap"] + "/bin/" + key if kind == "profile" else
                  paths["bootstrap"] + "/share/agent-storage/home-manager-files/" + relative)
        files.append({"path": inputs[key]["path"], "source": source, "kind": kind,
                      "known_sha256": sorted(known[key])})
    manifest = {"version": 1, "bootstrap": paths["bootstrap"], "files": files,
                "migration_enabled": paths["migration_enabled"]}
    temporary = state / ".desired.json.new"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(manifest, stream, indent=2)
        stream.write("\n")
    os.replace(temporary, state / "desired.json")
    units = home / ".config/systemd/user"
    for suffix, target in (("service", "default.target"), ("timer", "timers.target")):
        name = "agent-storage-restore." + suffix
        replace_symlink(units / name, paths["bootstrap"] + "/share/agent-storage/" + name)
        wants = units / (target + ".wants")
        wants.mkdir(exist_ok=True)
        replace_symlink(wants / name, "../" + name)
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "--user", "restart", "agent-storage-restore.timer"], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--build-only", action="store_true", help="build isolated outputs without installing (default)")
    mode.add_argument("--apply", action="store_true", help="build and install the isolated user-level outputs")
    args = parser.parse_args()
    home = Path.home()
    state = home / ".local/state/agent-storage-rollout"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (state / "restore.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        inputs, expression = collect_inputs(home)
        paths = build(expression)
        record = apply(home, inputs, paths) if args.apply else None
        if args.apply:
            install_persistence(home, inputs, paths)
    print(json.dumps({"built": paths, "record": record}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"install-agent-storage: {error}", file=sys.stderr)
        sys.exit(1)
