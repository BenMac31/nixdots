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

## The chrome it paints

gred's Vim window carries three bars along its bottom edge, and this paints
the same three, to the measures in `gred-rs/crates/gred/src/chrome.rs` and
`crates/ui/src/control.rs`:

| Bar | What | gred's measures |
|---|---|---|
| statusline | the mode pill, the keys held, the thread's name | `chrome::LINE` 24, the tag: 18 tall, radius 4, pad 7, caption 11 at weight 600, a ground and an ink per mode (`Theme::ink`'s `modes`) |
| which-key bar | a line per key that continues the pending prefix | `chrome::which_key`: columns of 220 filled top to bottom, rows of 22, 12 either end, 8 over and under, on the chrome with one hairline along its top; key chips 18 tall, radius 4, pad 5, mono-small on the sunken ground; a group's words in the accent |
| message line | the last thing said, under the statusline | `chrome::message_line`: 24 tall, on the page, 10 either end, Type::Small in the colour of its level |

The colours are read from T3's own `--app-theme-*` properties, so they follow
whatever theme is set; the fallbacks, and the mode pill's grounds, which are
no T3 role, are `Theme::ink`'s.

`look-check.html` is a rig for looking at them: open it, or

    chromium --headless=new --screenshot=look.png --window-size=1600,1000 \
      --virtual-time-budget=3000 "file://$PWD/look-check.html?seq=<leader>"

and compare with the rendered gred frames in
`docs/Tech/gred/native/frames/first-run-card/`.

## Waiting, as gred waits

`modal::Resolver`: "A sequence that is bound and also starts a longer one
waits for the timeout, Vim's `timeoutlen`, then runs. One that only leads on
waits as long as it takes where commands are typed, while the which-key bar
shows what can follow."

So `<leader>`, `<C-w>`, `]` and `[` wait for their next key as long as it
takes, and only `g`, which is vim's own command as well as the app's prefix,
is on a clock. `timeoutlen` is 300 ms, gred's default, and it is also how long
a prefix waits before the which-key bar comes up. `Escape` abandons a sequence
half typed.

`g` is shared with vim: `gt gT ga gd gD gr*` are the app's, any other key
after `g` goes to vim's own `g` (`gg gu gU g~`); a lone `g` that waits out
`timeoutlen` stays vim's `g`. `__t3vim.feedSeq("<leader>sf")` drives the trees
from devtools, and `__t3vim.said()` is the last thing on the message line.

The keydown listener is on `window` in the capture phase. The plugin runs
before T3's bundle, so it is registered ahead of T3's own handlers, and a key
it takes mid-sequence never reaches them.

## Out of the composer, into the conversation

In gred an agent's page is a read-only Vim buffer and the composer is a field
inside it (`fleet/src/page/keys.rs`). Escape in the composer's normal mode
with nothing typed of a command leaves it, and the conversation takes the
keys (`Composer::rests`, "where an escape would leave it", and page.rs's
`Typed::Leave`). The same two steps work here:

| Key | What |
|---|---|
| `Esc` `Esc` | insert to normal, then out of the composer |
| `j` `k` | the view a line down, up |
| `gg` `G` | the first line, the last |
| `<C-d>` `<C-u>` | half a screen |
| `<C-f>` `<C-b>` | a screen |
| `<C-e>` `<C-y>` | the view a line |
| `]]` `[[` | the next message, the one before |
| `][` `[]` | turn |
| `]t` `[t` | tool call |
| `i` `a` `I` `A` `o` | write to the agent again |
| `/` | search the conversation (`chat.find`) |

gred has a cursor line to move and T3's conversation has none, so `j` and `k`
move the view by a line, which is what `<C-e>` and `<C-y>` do. The rest of
gred's conversation keys are surfaces T3 has not: folds, `yy`, `K`, and the
labels `f` puts on links. `<C-c>` is left to the platform; gred's Vim keys
interrupt the turn with it, but here that would take copying a selection out
of the chat, and `<leader>ak` stops the agent.

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

## The theme

`graphide-verdigris-ink.json` is gred's Verdigris Ink as a T3 theme, built
from `graphide-verdigris-ink.css` by `build-theme.py` (T3 carries a theme's
CSS as one JSON string, which no diff can be read in; the stylesheet lives
beside it as a real stylesheet). Every colour is read from
`gred-rs/crates/ui/src/theme.rs`: `Theme::ink` and `Theme::marble` for the
palette, and `Docks::of_roles` for which role each surface takes, which is
where the sidebar gets the page's own ground rather than a lighter one.

Install it by copying it to `~/.t3/userdata/themes/` and selecting it, or with
the `t3_theme_set` MCP tool. The form it holds, rather than the hexes, is what
carries the look: hairlines instead of fills, no shadow anywhere, the eyebrow
on section headings, mono for keys, paths and the composer, radii of 4 to 8,
and the accent kept for the one thing to look at.

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
