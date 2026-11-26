"""Merge declarative preferences into a stopped Brave profile."""

import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import tempfile


def arguments(command_line):
    args = [arg for arg in command_line.decode().split("\0") if arg]
    # Zypak exposes a process title containing the whole command as argv[0].
    if len(args) == 1 and args[0].startswith("/app/brave/brave "):
        try:
            return shlex.split(args[0])
        except ValueError:
            return args[0].split()
    return args


def running(profile_root):
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            if (proc / "comm").read_text().strip() != "brave":
                continue
            args = arguments((proc / "cmdline").read_bytes())
        except (OSError, UnicodeError):
            continue
        if not args or any(arg.startswith("--type=") for arg in args):
            continue
        data_dir = next(
            (arg.split("=", 1)[1] for arg in args if arg.startswith("--user-data-dir=")),
            None,
        )
        if data_dir is not None:
            if Path(data_dir) == profile_root:
                return True
        elif args[0].startswith("/app/") and profile_root == (
            Path.home() / ".var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
        ):
            return True
    return False


def merge(current, wanted):
    for key, value in wanted.items():
        if isinstance(value, dict):
            if not isinstance(current.get(key), dict):
                current[key] = {}
            merge(current[key], value)
        else:
            current[key] = value


def update(path, wanted):
    if path.is_symlink():
        raise RuntimeError(f"Refusing to replace a symlink: {path}")
    current = json.loads(path.read_text()) if path.exists() else {}
    before = json.dumps(current, sort_keys=True)
    merge(current, wanted)
    if json.dumps(current, sort_keys=True) == before:
        return
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = path.with_name(path.name + ".before-nix-browser")
    if path.exists() and not backup.exists():
        shutil.copyfile(path, backup)
        backup.chmod(0o600)
    fd, temporary = tempfile.mkstemp(prefix=".nix-browser-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(current, out, separators=(",", ":"))
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main():
    settings = json.loads(Path(sys.argv[1]).read_text())
    root = Path(sys.argv[2])
    if running(root):
        print("Brave preferences will apply after fully quitting and reopening Brave.")
        return
    profiles = [p for p in root.iterdir() if p.is_dir() and not p.is_symlink()
                and (p / "Preferences").is_file()] if root.exists() else []
    if not profiles:
        profiles = [root / "Default"]
    for profile in profiles:
        update(profile / "Preferences", settings["preferences"])
    update(root / "Local State", settings["localState"])


if __name__ == "__main__":
    main()
