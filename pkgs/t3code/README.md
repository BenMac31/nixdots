# t3code, with vim in the chat composer

T3 Code ships no vim mode for its chat composer, and no amount of
configuration can add one. Its keybinding layer takes a single key plus
modifiers with no modal state, and its command registry holds no text-editing
command at all, so there is nothing a binding could even be pointed at. The
composer itself is a Tiptap (ProseMirror) contenteditable.

So `vim-composer.js` runs in the renderer, and `inject-vim.py` inlines it into
`app.asar` at build time. Set `ai.t3code.vimComposer = false` for a stock T3.

**A change here needs a rebuild, not a T3 restart.** The plugin lives inside
`app.asar`, so restarting T3 reloads the same bundle it already had. Run
`home-manager switch` and then relaunch T3. To check which build is live:

    grep -ac SEQ_ROWS "$(readlink -f ~/.nix-profile/bin/t3code | sed 's|/bin/t3code||')/lib/t3code/resources/app.asar"

A zero there means the running T3 predates the sequence engine, and the keys
in `~/.t3/userdata/keybindings.json` that the engine dispatches to will do
nothing. Worse, `<C-w>` then falls through to T3's own `mod+w`, which closes
the right panel.

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

## Graphide's key sequences

T3's keybindings take one chord per binding and no sequences, so the plugin
owns Graphide's key trees (`gred-rs/.../presets/gred.toml`, leader `<Space>`):
`<leader>...`, `<C-w>...`, `g...` and `]...` / `[...`. They run in the
composer's Normal and Visual modes and, with nothing editable focused,
anywhere in the app. Inputs, the terminal, menus, listboxes and dialogs keep
their own keys.

A completed sequence is dispatched as one synthetic `Ctrl+Alt+Shift+<key>`
keydown at `window`, which `~/.t3/userdata/keybindings.json` binds to the T3
command. At `window`, T3's `editableFocus` reads false. The key table is
`SEQ_ROWS` in `vim-composer.js`; a row with no T3 counterpart is still
consumed and shows a message instead. In the composer, `:` sends the command
palette's chord too.

`g` is shared with vim: `gt gT ga gd gD gr*` are the app's, any other key
after `g` goes to vim's own `g` (`gg gu gU g~`). An unfinished sequence drops
after `SEQ_TIMEOUT_MS` (1000 ms; a lone `g` that times out stays vim's `g`),
`Escape` drops it at once, and a which-key panel lists the next keys while one
is pending. `__t3vim.feedSeq("<leader>sf")` drives it from devtools.

The keydown listener is on `window` in the capture phase. The plugin runs
before T3's bundle, so it is registered ahead of T3's own handlers, and a key
it takes mid-sequence never reaches them.

## j and k in T3's lists

T3's thread list (the sidebar, and the thread panel, which is the same row
component) and the settings navigation are roving-tabindex lists: every row is
a `role="button"` with a `data-sidebar-row` or `data-settings-section`
attribute, and T3 listens on the list's container for the arrow keys, Home and
End. `workspace.focusPrevious` (`<C-h>`) lands on the current row.

With a row focused, the plugin turns `j k h l gg G` into the arrows, `Home`
and `End` that T3 already handles, dispatched at the row. Nothing about the
list is reimplemented here, so expanding a group, loading more and the scroll
into view stay T3's own. `Space` and `Enter` are left alone: they activate the
focused row, and the leader is not taken over a focused control. A thread
being renamed is an `input` inside a row, where every key stays its own.

`[data-sidebar-row]` and `[data-settings-section]` are the only two lists T3
drives this way. Its pickers are listboxes behind a text field, where a letter
has to stay a letter. The key trees stay out of focused controls: `<leader>`,
`g`, `]` and `[` run with nothing focused, not with a row focused.

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

## Reading T3's bundle

Finding what T3 itself does with a key (which lists it drives, what a command
is wired to) means reading `app.asar`, which is one 270 MB blob of
concatenated files, so a plain `grep` prints megabyte-long lines.
`probe-asar.py` slices a window around each hit instead:

    python3 -I probe-asar.py \
      "$(readlink -f ~/.nix-profile/bin/t3code | sed 's|/bin/t3code||')/lib/t3code/resources/app.asar" \
      data-sidebar-row 300 500 8

It is a reading tool only, and no part of the build. Names in the renderer
chunks are mangled and change with every T3 release, so read behaviour from it
and never bind to a name it shows.

## Tests

`./run-tests.sh` drives the plugin in headless Chromium against a DOM shaped
like Tiptap's, with a stand-in for the HardBreak extension. 269 cases, 130
of them for the key sequences and 14 for the list keys, those last against a
copy of T3's own list handler rather than an invented one, so they fail if the
keys the plugin sends stop being the keys T3 waits for.

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
