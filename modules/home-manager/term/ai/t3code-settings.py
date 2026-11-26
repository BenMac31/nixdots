"""Merge a provider-instance patch into T3 Code's settings.json.

T3 owns that file at runtime, so this reads it, folds in the instances Nix
declares (driver plus the config keys we set, leaving every other key alone)
and writes it back only when something actually changed.
"""

import json
import os
import sys
import tempfile

path, patch_path = sys.argv[1], sys.argv[2]

with open(patch_path) as stream:
    patch = json.load(stream)

try:
    with open(path) as stream:
        settings = json.load(stream)
except FileNotFoundError:
    settings = {}

changed = False
instances = settings.setdefault("providerInstances", {})
for instance_id, wanted in patch.get("providerInstances", {}).items():
    instance = instances.setdefault(instance_id, {})
    config = instance.setdefault("config", {})
    for key, value in {"driver": wanted["driver"]}.items():
        if instance.get(key) != value:
            instance[key] = value
            changed = True
    for key, value in wanted.get("config", {}).items():
        if config.get(key) != value:
            config[key] = value
            changed = True

if not changed:
    sys.exit(0)

os.makedirs(os.path.dirname(path), exist_ok=True)
fd, temporary = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings-")
with os.fdopen(fd, "w") as stream:
    json.dump(settings, stream, indent=2)
    stream.write("\n")
os.replace(temporary, path)
