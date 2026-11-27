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

gred has a cursor line to move and T3's conversation has none. Read as a page
instead, `j` and `k` take the step gred's own page keys take, `STEP` = 60
(`page/src/keys.rs`), so `j` moves the same distance in the chat as it does
in the preview. `<C-e>` and `<C-y>` stay the view a line, measured from the
conversation's own text rather than assumed.

The view glides rather than jumping: `ui::motion`'s GLIDE, a spring of
response 90 ms, written as the exponential that settles in that time. The
plugin writes `scrollTop` itself each frame instead of asking the app to
scroll, because the app's own smooth scrolling starts again on every key and
a held `j` then fights it. A scroller set to `scroll-behavior: smooth`
animates even a `scrollTop` written straight to it, which leaves the view
somewhere the glide did not put it and makes it give itself up a frame later,
so the glide holds the behaviour at `auto` for as long as it runs and hands
it back after. A key pressed while a glide runs adds to where the view is
going, so holding one reads as a single movement. Anything else that
moves the view, the wheel or T3 holding the end of a turn, wins: the glide
gives up rather than fighting it.

The rest of gred's conversation keys are surfaces T3 has not: the folds that
`h` and `l` open and close, `yy`, `K`, and the labels `f` puts on links.
`<C-c>` is left to the platform; gred's Vim keys interrupt the turn with it,
but here that would take copying a selection out of the chat, and
`<leader>ak` stops the agent.

## The agents' list

T3's thread list (the sidebar, and the thread panel, which is the same row
component) and the settings navigation are roving-tabindex lists: every row is
a `role="button"` with a `data-sidebar-row` or `data-settings-section`
attribute, and T3 listens on the list's container for the arrow keys, Home,
End, and `ContextMenu`/`Shift+F10` for the row's own menu. A group row carries
`aria-expanded`, and `ArrowRight` on a closed one clicks it.

With a row focused the plugin reads Graphide's agents'-list table,
`fleet/src/list/keys.rs`, whole. Every key of it is answered:

| key | what it does | how |
|---|---|---|
| `j k G gg l h` | the line below, above, last, first, into, fold | T3's own arrows, `Home`, `End` |
| `<C-d> <C-u>` | half the list | that many arrows: T3 handles no PageDown on a row |
| `dd` | stop and settle | `thread.settle` |
| `gp` | pin, or unpin | `thread.pin` |
| `K` | show or hide the details | `threadPanel.toggle` |
| `]c` `[c` | its change | `diff.toggle` |
| `<C-c>` | stop its turn | `thread.stop`, unless something is selected, which is a copy |
| `o` | a new agent | `chat.new` |
| `i` `a` `r` | write to the agent | opens the row, then the composer |
| `za zo zc` | toggle, open, close the group | the click T3's own `ArrowRight` makes |
| `zR zM` | open all, close all | that click on every group row |
| `zz` `dm` | snooze, archive, delete | the row's own menu, which T3 binds no key to |
| `n y A e V / f N . ! L x gd gb <C-x> <C-v> <C-t>` | - | T3 has nothing for these, and each says so |

Nothing about the list is reimplemented: expanding a group, loading more and
the scroll into view stay T3's own, so a release that changes the list changes
these keys with it. `Space` and `Enter` are left alone, since they activate the
focused row and the leader is not taken over a focused control. A thread being
renamed is an `input` inside a row, where every key stays its own.

The keys T3 cannot do say so on the message line rather than going dead. That
silence was most of what felt unfinished: six keys worked and thirty did
nothing at all.

`archive` and `delete` are the two gaps worth naming. T3 has them as row-menu
items only, not as commands, so no key can be bound to them: `dd` settles,
which moves the thread to the sidebar's Settled section, and `dm` opens the
menu where archive, delete and snooze live.

`[data-sidebar-row]` and `[data-settings-section]` are the only two lists T3
drives this way. Its pickers are listboxes behind a text field, where a letter
has to stay a letter.

## The panes

T3 marks each region of the window with `data-workspace-area` and
`data-workspace-order`: sidebar 0, conversation 1, composer 2, details 3,
panel 4, terminal 5. The order is the ring `workspace.focusNext` walks, and
that ring is the only movement T3 has a command for.

A ring is not a direction. Pointing all four of `<C-w>h j k l` at
`focusNext`/`focusPrevious` made `<C-w>h` and `<C-w>k` one key and `<C-w>j`
and `<C-w>l` another, so from the sidebar `<C-w>j` walked sideways into the
chat and `<C-w>k` walked back out of it. That is what felt clunky.

The direction is worked out here instead, by Graphide's own rule
(`gred/src/panes.rs::nearest`): of the panes lying that way, the closest whose
span crosses the focused pane's centre line, else the closest at all. Once the
target is known, T3's ring is stepped the short way round until the focus
arrives, rather than focusing an element directly, so T3 keeps its memory of
where the focus stood in each area and its focus-visible outline lands with
it.

`<C-h> <C-j> <C-k> <C-l>` are the same four directions bare, as gred binds
them beside the tree. Inside the terminal they stay the shell's, and `<C-w>`
then a direction is the way out, as it is in tmux.

`<C-w>c` and `<C-w>q` close the pane the focus is in, which is a different T3
command for each (`sidebar.toggle`, `terminal.close`, `rightPanel.close`,
`threadPanel.toggle`); in the chat and its composer they say it cannot be
closed rather than closing something else. `<C-w>o` shuts the others.
`<C-w>w` and `<C-w>p` are the ring itself. `<C-w>=`, `<C-w>x`, `<C-w>HJKL`
and the four resize keys have no T3 counterpart: T3's panes are dragged, and
nothing in its command table moves or sizes one.

## What it covers

Modes (normal, insert, visual, visual line), counts, operators `d c y > <
gu gU g~` with doubled forms, motions `h j k l w W b B e E 0 ^ $ gg G { } %
f F t T ; ,`, text objects `iw aw i" a" i' a' i` a` i( a( i[ a[ i{ a{`, and
`x X D C Y s S p P r ~ J u Ctrl-r i I a A o O v V .`, plus `"+` for the
system clipboard. Vim's own `cw`-behaves-like-`ce` special case is honoured.

Not covered: `/` and `?` search, ex commands, named registers other than `+`,
and marks.

Insert mode passes every key straight through, so T3's own send, mentions,
slash commands and completion behave exactly as they do without this, with
three exceptions: vim's erasers `<C-w>` a word, `<C-h>` a character and
`<C-u>` back to the start of the line. Graphide's own line editor has the
same three (`ui/src/line.rs`), and T3 had all three bound elsewhere, so while
typing `<C-w>` closed the right panel, `<C-u>` opened the usage page and
`<C-h>` stepped the pane ring.

In normal mode anything with a modifier is left to T3's keybindings, except
`Ctrl-r` for redo and the four pane directions, and `Enter` always sends.
`dd` with the composer empty settles the thread, which is what Graphide's own
composer does with it: "gred's own composer sends `dd` as the agents' list
does, and archives" (`fleet/src/composer.rs`). On a line with anything on it,
whitespace included, `dd` still deletes the line.

## The preview's keys

gred drives a web page with a grammar of its own
(`gred-rs/crates/page/src/keys.rs`), and `page-vim.js` is that table inside
T3's preview. T3's preview is an Electron `<webview>` whose preload,
`preview-pick-preload.cjs`, already listens for keydown in its own JavaScript
world; the build appends this to it, so it sees the page's keys and its DOM
without touching T3's own code.

| Key | What |
|---|---|
| `j` `k` `h` `l` | a step, 60 px, as gred's STEP |
| `d` `u` `<C-d>` `<C-u>` | half a pane |
| `<C-f>` `<C-b>` | a pane |
| `<C-e>` `<C-y>` | a line, 40 px |
| `gg` `G` `0` `$` `N%` | the top, the bottom, the far left and right, that share down |
| `H` `L` `r` | back, forward, load again |
| `gu` `gU` | up a level of the address, the site's root |
| `g<C-a>` `g<C-x>` `.` | count the address's last number, and do that again |
| `]]` `[[` | heading; `]l` `[l` link, `]f` `[f` field, `]t` `[t` table, `]c` `[c` code |
| `f` `F` | a label on everything in view; `F` opens a link in a new tab |
| `m<x>` `'<x>` `` `<x> `` | mark the place, go back to it |
| `yy` `yt` `ym` | the address, the title, a Markdown link |
| `gi` | type in a field |
| `i` | every key to the page, until `<S-Esc>` |
| `<C-v>` | the next key is the page's |
| `o` `O` `/` `?` `+` `-` `=` | the address bar, the find bar, the zoom |

The scrolls glide, as gred's do, and they move the area under the point:
where the pointer last pressed, else the page. A field that has the keys
keeps them, and Escape leaves it.

The last row goes back to T3, since only the app can run them: the preload's
own `preview:page-unhandled-shortcut` channel carries the chord T3 already
binds for that command (`mod+=`, `mod+-`, `mod+0`, `alt+shift+l`,
`alt+shift+f`), so no new binding is needed and this names no T3 command.

Not carried over: gred's `;` verbs (right click, save, rapid labels), `gO`'s
outline, `gs`'s source, `n` and `N` once T3's find bar owns the find, and the
Visual rows, which are the page's own selection. `f`'s labels are the keys
`ui::hints` uses, home row first, with no label a prefix of another.

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

## The other half of the table

`keybindings.json` here is T3's whole keybindings table, installed to
`~/.t3/userdata/keybindings.json` at activation by `t3code-keys.py`. It and
`vim-composer.js` are one key table split in two: the plugin owns every modal
key and every sequence, and reaches a T3 command the only way a renderer
script can, by dispatching a private `Ctrl+Alt+Shift+<key>` chord at `window`
that this table maps to the command. Dispatched at `window`, T3's
`editableFocus` reads false, so a command guarded against a focused text box
still runs from the composer.

It is the whole table rather than a patch because T3 appends its own default
for any command no row holds: a key left out comes back on the next start.
That also caps it at 256 rules, and there are 147.

`check-chords.py` runs in the build and fails it if the plugin sends a chord
nothing binds, since such a key eats the press and does nothing, which is
worse than either half alone. `mod` is `ctrl` on Linux, which the check knows.

The 40 private chords are an implementation detail, not keys to press. The
keys to press are Graphide's, and the one-chord half of them is rebound to
gred's own: `:` for the command line, `<C-.>` for the agents, `<C-;>` for the
harness, `<C-,>` where a new agent starts, `<C-S-;>` for its terminal, `<C-o>`
and `<C-i>` for the jump list.

What was in `keybindings.json` before Nix first wrote it is kept beside it as
`keybindings.json.before-nix`.

## Off switches

* `ai.t3code.vimComposer = false` in home-manager, then rebuild.
* `ai.t3code.keybindings = false` leaves `~/.t3/userdata/keybindings.json`
  alone. The sequences then eat their keys and do nothing, since the chords
  they send are unbound; the modal editing still works.
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

`./run-tests.sh` drives both layers in headless Chromium: the composer and
the app against a DOM shaped like T3's window, with a stand-in for the
HardBreak extension, and `page-vim.js` against a page with something to
scroll, label, walk and mark. 321 cases and 29.

The fixture is T3's own shapes rather than invented ones: the list tests run
against a copy of T3's list handler, the pane tests against its workspace
areas and a copy of its focus ring, and the chat tests against its timeline
rows. They fail if the keys the plugin sends stop being the keys T3 waits
for, which is the point: nothing here binds to a minified name, so the shapes
are the contract.

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
