#!/usr/bin/env bash
# Exercise vim-composer.js in headless Chromium against a Tiptap-shaped DOM.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="${CHROME:-$(command -v chromium || true)}"
if [ -z "$CHROME" ]; then
  CHROME=$(nix build --no-link --print-out-paths nixpkgs#chromium)/bin/chromium
fi

# Chromium's singleton socket path overflows under a long TMPDIR, so keep it short.
D="${XDG_RUNTIME_DIR:-/tmp}/t3vim-test"
rm -rf "$D"; mkdir -p "$D"
trap 'rm -rf "$D"' EXIT

TMPDIR="$D" "$CHROME" --headless=new --disable-gpu --no-sandbox --no-first-run \
  --user-data-dir="$D/profile" --virtual-time-budget=15000 \
  --dump-dom "file://$PWD/test-vim-composer.html" 2>/dev/null \
  | python3 -c '
import sys, re, html
d = sys.stdin.read()
m = re.search(r"<pre id=\"out\">(.*?)</pre>", d, re.S)
if not m:
    sys.exit("no test output; chromium failed to run the page")
report = html.unescape(m.group(1))
print(report)
sys.exit(0 if re.search(r"FAIL 0$", report.strip()) else 1)
'
