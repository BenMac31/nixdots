import json
import os
import sys
import tempfile

path, claude = sys.argv[1], sys.argv[2]

try:
    with open(path) as stream:
        settings = json.load(stream)
except FileNotFoundError:
    settings = {}

instances = settings.setdefault("providerInstances", {})
claude_agent = instances.setdefault("claudeAgent", {"driver": "claudeAgent"})
config = claude_agent.setdefault("config", {})
if config.get("binaryPath") == claude:
    sys.exit(0)
config["binaryPath"] = claude

os.makedirs(os.path.dirname(path), exist_ok=True)
fd, temporary = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings-")
with os.fdopen(fd, "w") as stream:
    json.dump(settings, stream, indent=2)
    stream.write("\n")
os.replace(temporary, path)
