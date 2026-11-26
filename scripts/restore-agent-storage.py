#!/usr/bin/env python3
"""Restore a verified storage rollout after a known older Home Manager activation."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def plan(manifest, store_root=Path("/nix/store")):
    """Validate every input before changing any profile or link."""
    if manifest.get("version") != 1:
        raise ValueError("unsupported storage restore manifest")
    bootstrap = manifest["bootstrap"]
    if (Path(bootstrap).parent != store_root
            or not re.fullmatch(r"[a-z0-9]{32}-agent-storage-bootstrap", Path(bootstrap).name)):
        raise ValueError("invalid bootstrap path")
    changes = []
    for item in manifest["files"]:
        source, path = Path(item["source"]), Path(item["path"])
        if not str(source).startswith(bootstrap + "/") or ".." in source.parts:
            raise ValueError("restore source outside rooted bootstrap")
        if item["kind"] not in {"link", "profile"}:
            raise ValueError("invalid restore entry kind")
        expected = digest(source)
        try:
            current = digest(path)
        except FileNotFoundError:
            current = None
        if current == expected:
            continue
        if current is not None and current not in item["known_sha256"]:
            raise ValueError(f"unrecognized changes preserved: {path}")
        if item["kind"] == "link" and path.exists() and not path.is_symlink():
            raise ValueError(f"non-symlink preserved: {path}")
        changes.append(item)
    return changes


def replace_link(path, source):
    path = Path(path)
    with tempfile.TemporaryDirectory(prefix=".agent-storage-", dir=path.parent) as temp:
        link = Path(temp) / "link"
        link.symlink_to(source)
        os.replace(link, path)


def restore(manifest, nix, systemctl):
    state = subprocess.check_output([systemctl, "show", "home-manager-greencheetah.service",
                                     "-p", "ActiveState", "--value"], text=True).strip()
    if state in {"activating", "deactivating"}:
        return {"deferred": "Home Manager is activating"}
    changes = plan(manifest)
    if any(item["kind"] == "profile" for item in changes):
        entries = json.loads(subprocess.check_output([nix, "profile", "list", "--json"], text=True))["elements"]
        owned = []
        for name, entry in entries.items():
            paths = entry.get("storePaths", [])
            if len(paths) == 1 and re.fullmatch(r"/nix/store/[a-z0-9]{32}-agent-storage-bootstrap", paths[0]):
                owned.append(paths[0])
            elif name == "agent-storage-bootstrap":
                raise ValueError("bootstrap profile name belongs to an unrelated entry")
        if len(owned) > 1:
            raise ValueError("multiple storage bootstrap profile entries")
        for path in owned:
            subprocess.run([nix, "profile", "remove", path], check=True)
        subprocess.run([nix, "profile", "install", "--priority", "-20", manifest["bootstrap"]], check=True)
    for item in changes:
        if item["kind"] == "link":
            replace_link(item["path"], item["source"])
    for item in manifest["files"]:
        if digest(item["path"]) != digest(item["source"]):
            raise RuntimeError(f"restoration did not take effect: {item['path']}")
    stale_manager = False
    for item in manifest["files"]:
        if item["kind"] != "link" or not item["path"].endswith(".service"):
            continue
        expected = re.search(r"^ExecStart=(\S+)", Path(item["source"]).read_text(), re.M)
        if expected:
            loaded = subprocess.check_output([systemctl, "--user", "show", Path(item["path"]).name,
                                               "-p", "ExecStart", "--value"], text=True)
            stale_manager |= expected[1] not in loaded
    if changes or stale_manager:
        subprocess.run([systemctl, "--user", "daemon-reload"], check=True)
        if not manifest["migration_enabled"]:
            state = subprocess.check_output([systemctl, "--user", "show", "agent-scratch-migrate.timer",
                                             "-p", "LoadState", "--value"], text=True).strip()
            if state != "not-found":
                subprocess.run([systemctl, "--user", "stop", "agent-scratch-migrate.timer"], check=True)
                subprocess.run([systemctl, "--user", "disable", "agent-scratch-migrate.timer"], check=True)
            state = subprocess.check_output([systemctl, "--user", "show", "agent-scratch-migrate.service",
                                             "-p", "ActiveState", "--value"], text=True).strip()
            if state == "inactive":
                # The unit orders us before migration, so cancel a pending start
                # without interrupting a copy that was already running.
                subprocess.run([systemctl, "--user", "stop", "--no-block", "agent-scratch-migrate.service"], check=True)
        subprocess.run([systemctl, "--user", "restart", "agent-storage-cleanup.timer", "gp-cache-prune.timer"], check=True)
        subprocess.run([systemctl, "--user", "start", "--no-block", "agent-storage-cleanup.service",
                        "gp-cache-prune.service"], check=True)
    return {"restored": [item["path"] for item in changes]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--nix", default="nix")
    parser.add_argument("--systemctl", default="systemctl")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if not args.manifest.exists():
        return
    with (args.manifest.parent / "restore.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # A current declarative activation may retire the repair while we wait.
        if not args.manifest.exists():
            return
        manifest = json.loads(args.manifest.read_text())
        result = {"pending": plan(manifest)} if args.check else restore(manifest, args.nix, args.systemctl)
        print(json.dumps(result))


if __name__ == "__main__":
    main()
