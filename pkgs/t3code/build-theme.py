#!/usr/bin/env python3
"""Fold graphide-verdigris-ink.css into graphide-verdigris-ink.json.

T3 carries a theme's CSS as one JSON string, which is unreadable and
unreviewable in a diff. The CSS lives beside it as a real stylesheet and this
writes it in, so the .json in this directory is generated from the .css and
the two never drift.

    python3 -I build-theme.py [out.json]

With no argument it rewrites the .json in place. The theme is installed by
`t3_theme_set` or by copying the result to
~/.t3/userdata/themes/graphide-verdigris-ink.json.
"""
import json
import pathlib
import sys

here = pathlib.Path(__file__).parent
theme_path = here / "graphide-verdigris-ink.json"
css_path = here / "graphide-verdigris-ink.css"

theme = json.loads(theme_path.read_text())
theme["css"] = css_path.read_text().strip()

out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else theme_path
out.write_text(json.dumps(theme, indent=2) + "\n")
print("%s: %d colour roles, %d bytes of css" % (out, len(theme["colors"]), len(theme["css"])))
