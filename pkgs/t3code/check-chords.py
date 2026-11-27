#!/usr/bin/env python3
"""Check that every chord vim-composer.js sends is a chord keybindings.json binds.

The two files are one key table split in two. vim-composer.js owns the modal
keys and the sequences, and reaches T3's commands the only way a renderer
script can: it dispatches a private Ctrl+Alt+Shift chord at `window`, and
keybindings.json maps that chord to the command. A sequence pointing at a
chord nothing binds is silently dead - the key is eaten and nothing happens,
which is the worst of both - and nothing else notices, so this does.

Usage: check-chords.py vim-composer.js keybindings.json
"""

import json
import re
import sys

js_path, table_path = sys.argv[1], sys.argv[2]
js = open(js_path).read()
table = json.load(open(table_path))

# `mod` is meta on macOS and ctrl on Linux, which is the only platform this
# package builds for, so mod+alt+shift+a and ctrl+alt+shift+a are one chord.
bound = {}
for rule in table:
    key = rule["key"]
    for prefix in ("ctrl+alt+shift+", "mod+alt+shift+"):
        if key.startswith(prefix):
            bound.setdefault(key[len(prefix):], rule["command"])

# A row of SEQ_ROWS or LIST_ROWS: ["keys", "chord" | "@act" | null, "desc"].
used = {}
for match in re.finditer(r'\["([^"]+)",\s*("(?:[^"\\]|\\.)*"|null),\s*"', js):
    chord = match.group(2)
    if chord == "null":
        continue
    chord = chord[1:-1]
    if chord.startswith("@"):
        continue
    used.setdefault(chord, match.group(1))
for match in re.finditer(r'dispatchChord\("([^"]+)"\)', js):
    used.setdefault(match.group(1), "a direct send")
for match in re.finditer(r'^\s+(sidebar|terminal|panel|details):\s*"([^"]+)"', js, re.M):
    used.setdefault(match.group(2), "closing the " + match.group(1))

if not used:
    sys.exit("check-chords: found no chords at all, so the patterns have gone stale")

missing = sorted((chord, where) for chord, where in used.items() if chord not in bound)
for chord, where in missing:
    print(f"check-chords: {where} sends Ctrl+Alt+Shift+{chord}, which nothing binds",
          file=sys.stderr)
if missing:
    sys.exit(1)

print(f"check-chords: {len(used)} chords, every one of them bound")
