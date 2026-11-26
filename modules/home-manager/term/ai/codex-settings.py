import os
from pathlib import Path
import sys
import tempfile

import tomlkit


path = Path(sys.argv[1]).resolve()
original = path.read_text() if path.exists() else ""
settings = tomlkit.parse(original)
if "agents" not in settings:
    settings["agents"] = tomlkit.table()
agents = settings["agents"]
agents.pop("max_threads", None)
agents["max_concurrent_threads_per_session"] = 32
updated = tomlkit.dumps(settings)
if updated != original:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".codex-settings-")
    try:
        with os.fdopen(fd, "w") as output:
            output.write(updated)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
