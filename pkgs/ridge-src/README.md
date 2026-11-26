# ridge

Fingerprint enrollment and verification, inline in your shell. A compact Unicode
Braille fingerprint reacts to touch, reading, and results; accepted enrollment
stages fill its ridges with color. The display stays in terminal scrollback and
your shell prompt returns when the operation finishes.

The illustration reflects reader events and enrollment progress. It does not
show your actual fingerprint image or measured ridge coverage.

## Commands

- `ridge` or `ridge verify`: verify once, then return success or failure.
- `ridge verify --watch`: repeat scans, leave results in scrollback, and show totals.
- `ridge enroll right-index-finger`: enroll a new finger with live progress.
- `ridge list`: list enrolled fingers.
- `ridge delete right-index-finger`: delete one finger after explicit confirmation.
- `ridge --demo`: run a short enrollment preview without opening the reader.

Ctrl+C cancels and releases the reader. No alternate screen or raw keyboard mode
is used. Animation goes to stderr; the final success result goes to stdout.
Pipes and `TERM=dumb` get plain progress messages. `--plain` disables animation,
and `NO_COLOR=1` keeps the animation without color. Braille and Unicode symbols
use ordinary terminal fonts and do not require Nerd Fonts or font ligatures.

Verification returns exit status 0 for a match, 1 for a nonmatch or error, and
130 when cancelled. Ending `--watch` with Ctrl+C prints the totals and returns 0.

Requires a working system `fprintd` service and its usual PolicyKit permissions.
The reader is claimed while scanning; close other fingerprint prompts first.
Build with `cargo build --release` or the accompanying Nix package.

The NixOS configuration keeps a portable source snapshot at
`~/nixos/pkgs/ridge-src`. After changing this project, copy `Cargo.toml`,
`Cargo.lock`, `README.md`, and `src/` there before rebuilding the package.
