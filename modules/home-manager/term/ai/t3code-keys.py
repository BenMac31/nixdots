"""Install T3 Code's keybindings table from the one Nix declares.

The table that gives T3 Graphide's keys lived only as hand edits in
~/.t3/userdata/keybindings.json, so it was on this machine and nowhere else.
Nix owns it now: pkgs/t3code/keybindings.json is the whole table, and this
writes it when it differs.

Two things about that file decide the shape of this script.

T3 writes it itself. On a start where the file is missing it writes its own
defaults, and on every start it appends any default whose *command* no row
holds. So the table has to name every command it rebinds, or T3 puts its own
chord back beside ours; the table is checked for that rather than trusted.

It is also read while the app runs, so the new table goes to a temporary file
beside it and is renamed over it, which no reader can see half of. What was
there the first time is kept once, as keybindings.json.before-nix, so a hand
edit made before this existed is not simply gone.
"""

import json
import os
import sys
import tempfile

path, table_path = sys.argv[1], sys.argv[2]

with open(table_path) as stream:
    table = json.load(stream)

if not isinstance(table, list) or not table:
    sys.exit("t3code-keys: the declared table is not a list of rules")
if len(table) > 256:
    sys.exit(f"t3code-keys: {len(table)} rules, and T3 caps the file at 256")

# One key may carry several rules (different `when`), but two rules with the
# same key and the same `when` make the earlier one dead weight.
seen = set()
for rule in table:
    mark = (rule.get("key"), rule.get("when", ""))
    if mark in seen:
        sys.exit(f"t3code-keys: {mark[0]!r} is bound twice under the same when")
    seen.add(mark)

try:
    with open(path) as stream:
        live = json.load(stream)
except (FileNotFoundError, ValueError):
    live = None

if live == table:
    sys.exit(0)

folder = os.path.dirname(path)
os.makedirs(folder, exist_ok=True)

keep = path + ".before-nix"
if live is not None and not os.path.exists(keep):
    with open(keep, "w") as stream:
        json.dump(live, stream, indent=2)
        stream.write("\n")

fd, temporary = tempfile.mkstemp(dir=folder, prefix=".keybindings-")
with os.fdopen(fd, "w") as stream:
    json.dump(table, stream, indent=2)
    stream.write("\n")
os.replace(temporary, path)
