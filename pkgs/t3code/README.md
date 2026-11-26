# t3code, with vim in the chat composer

T3 Code ships no vim mode for its chat composer, and no amount of
configuration can add one. Its keybinding layer takes a single key plus
modifiers with no modal state, and its command registry holds no text-editing
command at all, so there is nothing a binding could even be pointed at. The
composer itself is a Tiptap (ProseMirror) contenteditable.

So `vim-composer.js` runs in the renderer, and `inject-vim.py` inlines it into
`app.asar` at build time. Set `ai.t3code.vimComposer = false` for a stock T3.

## How the plugin talks to the editor

Nothing here reads a minified symbol. Every edit goes through a web platform
API or ProseMirror's own keymap, both of which are stable across T3 releases:

| what | how |
|---|---|
| motions | a DOM Range over a text/offset map built from the live DOM |
| deletes | `execCommand('delete')`, then `forwardDelete` to join blocks |
| inserts | `execCommand('insertText')` |
| newline | synthetic `Shift-Enter` on `view.dom`, which HardBreak binds |
| undo, redo | synthetic `Mod-z` / `Shift-Mod-z`, which History binds |

Synthetic events carry `bubbles: false` and are dispatched straight at
`view.dom`, where ProseMirror attaches its listeners, so T3's React tree never
sees them. The handler ignores anything with `isTrusted === false`, so these
never feed back into it.

## What it covers

Modes (normal, insert, visual, visual line), counts, operators `d c y > <
gu gU g~` with doubled forms, motions `h j k l w W b B e E 0 ^ $ gg G { } %
f F t T ; ,`, text objects `iw aw i" a" i' a' i` a` i( a( i[ a[ i{ a{`, and
`x X D C Y s S p P r ~ J u Ctrl-r i I a A o O v V .`, plus `"+` for the
system clipboard. Vim's own `cw`-behaves-like-`ce` special case is honoured.

Not covered: `/` and `?` search, ex commands, named registers other than `+`,
and marks.

Insert mode passes every key straight through, so T3's own send, mentions,
slash commands and completion behave exactly as they do without this. In
normal mode anything with a modifier is left to T3's keybindings, except
`Ctrl-r` for redo, and `Enter` always sends.

## Off switches

* `ai.t3code.vimComposer = false` in home-manager, then rebuild.
* No rebuild: `__t3vim.disable()` in devtools, or set
  `localStorage['t3code:vim-composer'] = 'off'`.

If a T3 release moves the renderer entry point, `inject-vim.py` fails the
build rather than shipping a half-patched bundle. Turn the flag off to get a
working T3 back in one rebuild, then fix the injector.

## Tests

`./run-tests.sh` drives the plugin in headless Chromium against a DOM shaped
like Tiptap's, with a stand-in for the HardBreak extension. 92 cases.

`CHROME=/path/to/chromium ./run-tests.sh` to skip the nixpkgs build.

Four browser behaviours the tests pinned down, each the cause of a real bug:

* Chromium rewrites a leading or trailing space in a contenteditable as
  U+00A0, which hid word boundaries.
* A caret placed just after a trailing `<br>` is canonicalised back in front
  of it, so inserting a break and then typing put the text on the wrong side.
  Breaks now go in last, back to front.
* `execCommand('delete')` over a range that ends on a block boundary deletes
  the text without joining the blocks, and emptying a paragraph sometimes
  removes it outright. Deletes are taken apart per line and the seams joined
  convergently.
* `<p><br></p>` is one empty line, not two: a `<br>` with nothing after it
  inside its own block is a placeholder.
