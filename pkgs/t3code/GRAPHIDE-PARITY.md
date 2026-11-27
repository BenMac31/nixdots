# Graphide parity for T3 Code's keys

Ben drives Graphide's native app with `editing = "vim"` and leader `<Space>`.
This file records how far T3 Code can follow it, where it cannot, and why. The
spec it is measured against is

    graphide-ide/gred-rs/crates/gred/src/presets/gred.toml

Read that file, not this one, when you want to know what a key does in
Graphide. This one only records the mapping.

## The three layers a key can land in

| Layer | File | Sequences? | Modal? |
|---|---|---|---|
| T3's app chrome | `keybindings.json` here, installed to `~/.t3/userdata/` | no, one chord per binding | no |
| T3's composer, lists, panes and chat | `vim-composer.js` here | yes, it owns them | yes |
| T3's preview | `page-vim.js` here | yes | yes |
| Claude Code's TUI | `~/.claude/keybindings.json` | yes, space separated | per context |

The first two are one table split in two, and `check-chords.py` fails the
build if the plugin sends a chord the table does not bind: such a key eats the
press and does nothing, which is worse than either half alone.

T3's own binding engine takes `{key, command, when?}` and its key parser
splits on `+` only. A second key is a hard error, so the whole `<Space>` tree,
the `<C-w>` tree and `g`/`]`/`[` are inexpressible there. That is why
`vim-composer.js` owns the trees and dispatches a single private chord
(`ctrl+alt+shift+<key>`) that `keybindings.json` binds. The chord is an
implementation detail; nobody is meant to type it.

The engine runs in the composer's normal and visual modes and also with
nothing editable focused, because in Graphide normal mode is global: `<C-w>`
and `gt` are least useful inside a composer. It stands aside on anything that
wants the keys itself, which includes the terminal and, deliberately, every
control that Space activates: buttons, checkboxes, switches, tabs, menu items,
tree items. Taking the leader over a focused button would break Space on that
button for the sake of a leader nobody presses with a button focused. The cost
is that Space no longer pages a scroll area; PageDown still does.

One set of keys does run on a focused control: Graphide's agents'-list table
on a list row, below.

## The agents' list

Graphide's workflow for the agents panel is `<C-h>` into the pane, then the
list's own table down and across it. The spec is a second file,

    graphide-ide/gred-rs/crates/fleet/src/list/keys.rs

and its 43 rows are ported whole. T3's own list handler listens for
`ArrowUp`, `ArrowDown`, `ArrowLeft`, `ArrowRight`, `Home`, `End` and
`ContextMenu`/`Shift+F10` on the list's container, and clicks a group row to
open it, so every act that can be expressed in those is, and the rest go to a
T3 command or say there is none.

| Graphide | act | T3 |
|---|---|---|
| `j` `k` `G` `gg` | down, up, last, first | `ArrowDown` `ArrowUp` `End` `Home` |
| `l` `h` | into the line, fold the group | `ArrowRight` `ArrowLeft` |
| `<C-d>` `<C-u>` | half the list | that many arrows: no PageDown is handled |
| `dd` `<C-CR>` | stop and archive | `thread.settle` |
| `gp` | pin, or unpin | `thread.pin` |
| `K` | the details | `threadPanel.toggle` |
| `]c` `[c` | its change | `diff.toggle` |
| `<C-c>` | interrupt | `thread.stop`, unless there is a selection to copy |
| `o` | a new agent | `chat.new` |
| `i` `a` `r` | write to it | the row is opened, then the composer |
| `za` `zo` `zc` | the group | the click T3's `ArrowRight` makes |
| `zR` `zM` | every group | that click on each group row |
| `zz` | snooze | the row's menu, where T3 keeps snooze |
| `n` `y` `A` `e` | answer what it asks | none: T3 answers in the conversation, not the list |
| `V` | a selection of lines | none: T3 selects no rows |
| `/` | filter the list | none: T3 has no sidebar search |
| `f` | label the preview's links | none |
| `N` | the agent before that asks | none |
| `.` | the last change again | none |
| `!` `L` | important, later | none |
| `x` | switch that computer off | none |
| `gd` `gb` | its file, bring it back | none |
| `<C-x>` `<C-v>` `<C-t>` | below, beside, a new tab | none: T3 opens a thread in one place |
| `<Tab>` `<S-Tab>` | mark and move | left to T3, which uses Tab for focus |

Two gaps are worth naming. `thread.settle` is not Graphide's archive: it moves
the thread to the sidebar's Settled section rather than out of the list.
T3's real `archive` and `delete` are row-menu items with no command behind
them, so no key can be bound to either; `dm` opens that menu, beside `zz`.

No part of the list is reimplemented: expanding a group, "load more" and the
scroll into view stay T3's own behaviour, and a T3 release that changes the
list changes these keys with it.

This covers `[data-sidebar-row]` (the sidebar and the thread panel, one row
component) and `[data-settings-section]` (the settings navigation, the same
shape without Left and Right). They are the only two lists T3 drives with the
arrows; its pickers are listboxes behind a text field, where a letter has to
stay a letter, and a thread being renamed is an `input` inside a row, where
every key stays its own.

`Space` and `Enter` keep activating the focused row, so the leader is the one
tree that does not start on one. `g`, `]` and `[` do: the app's tree gets the
first key and the list gets the second through the fall-through, which is how
`gg`, `gp` and `]c` land. That is the order Graphide resolves them in too,
the keymap first and the surface's own keys after it.

## The panes

The spec is `gred/src/panes.rs` and the `<C-w>` block of `gred.toml`. T3 marks
each region with `data-workspace-area` and `data-workspace-order`, and the
order is the ring `workspace.focusNext` walks:

| area | order |
|---|---|
| sidebar, settings-nav | 0 |
| conversation, home, pull-requests, settings | 1 |
| composer | 2 |
| details | 3 |
| panel | 4 |
| terminal | 5 |

That ring is the only movement T3 has a command for, and a ring is not a
direction. All four of `<C-w>h j k l` pointed at `focusNext`/`focusPrevious`,
which made `<C-w>h` and `<C-w>k` one key and `<C-w>j` and `<C-w>l` another:
from the sidebar `<C-w>j` walked sideways into the chat, and `<C-w>k` walked
back out of it.

The direction is decided from the rectangles instead, by `panes.rs::nearest`:
of the panes lying that way, the closest whose span crosses the focused pane's
centre line, else the closest at all, with `EPS = 0.5` so a shared border
counts as touching. The visibility test is T3's own, copied from its focus
module, so this skips exactly the areas the ring skips. Then T3's ring is
stepped the short way round until the focus arrives, which keeps its memory of
where the focus stood in each area and its focus-visible outline.

| Graphide | T3 |
|---|---|
| `<C-w>h j k l`, and bare `<C-h> <C-j> <C-k> <C-l>` | the direction, then the ring |
| `<C-w>w` `<C-w>p` | the ring itself (vim's; `gred.toml` omits them) |
| `<C-w>c` `<C-w>q` | the focused pane's own close command |
| `<C-w>o` | every other pane's |
| `<C-w>s` `<C-w>v` | `terminal.split`, `terminal.splitVertical` |
| `<C-w>T` | `rightPanel.new` |
| `<C-w>=` `<C-w>x` `<C-w>HJKL` `<C-w>> < + -` | none: T3's panes are dragged, and no command moves or sizes one |

Inside the terminal the bare four stay the shell's, and `<C-w>` then a
direction is the way out, as it is in tmux. In the chat and its composer
`<C-w>c` says the chat cannot be closed rather than closing something else.

## The look

Ben runs gred's Vim window on Verdigris Ink (`[gred] base = "gred"`,
`theme = "ink"`, `chrome = "minimal"`, density 1). Two things carry that look
into T3, and both are read from the source rather than guessed:

* **The theme**, `graphide-verdigris-ink.json` in this directory. Colours from
  `Theme::ink` and `Theme::marble`; which surface takes which role from
  `Docks::of_roles`, whose test pins `docks.sidebar == theme.page` and
  `docks.statusbar == theme.chrome`. So the sidebar is the page's own ground
  with a hairline beside it, not a lighter panel, the chrome is the darkest
  surface, and `raised` is for what floats: dialogs, menus, cards.
* **The chrome this plugin paints**: the statusline, the which-key bar and the
  message line, to `chrome.rs`'s measures. See the README.

The rendered frames in `docs/Tech/gred/native/frames/first-run-card/` are the
thing to check against: `-gred-` is the Vim window, `-standard-` the windowed
shell, `-ink-` and `-marble-` the two themes.

What cannot be carried over: gred's panes, its tab line, the map, and the rest
of the statusline's segments (the branch, the position, the agents' counts),
which are gred's own surfaces and have no T3 counterpart.

## The `when` grammar

T3's `when` grammar is `!`, `&&`, `||` and parens over these context keys, and
nothing else: `terminalFocus`, `terminalOpen`, `previewFocus`, `previewOpen`,
`editableFocus`, `modelPickerOpen`, `usagePageOpen`, `rightPanelOpen`,
`composerFocus`, `turnRunning`, `draftThreadRoute`, `isMac`, `isDesktop`,
`isWeb`. A key absent at a dispatch site reads as false, so `!editableFocus`
is always true at the handlers that do not supply it. Only these commands go
through the shared handler that always computes `editableFocus` from the event
target, so only these are safe to put on a bare or shifted key:
`appearance.cycle`, `chat.new`, `chat.newWithoutProject`,
`commandPalette.toggle`, `filePicker.toggle`, `navigation.back`,
`navigation.forward`, `preview.find`, `preview.toggle`,
`projectSearch.toggle`, `theme.select`, `themeEditor.toggle`, `usage.open`,
`thread.undo`.

## Graphide chords that port exactly

| Graphide | T3 key | command |
|---|---|---|
| `<C-h> <C-j> <C-k> <C-l>` pane left/down/up/right | the plugin's, not a binding | the direction, then `workspace.focusNext`/`focusPrevious` |
| `<C-o>` / `<C-i>` jump back/forward | `ctrl+o` / `ctrl+i`, `!editableFocus` | navigation.back / forward |
| `<C-.>` agents.toggle | `ctrl+.` | sidebar.toggle |
| `<C-;>` agent.harness | `ctrl+;` | modelPicker.toggle |
| `<C-S-;>` agent.terminal | `ctrl+shift+;` | terminal.toggle |
| `<C-,>` agent.place | `ctrl+,` | composer.workspace |
| `<C-x>` agent.actions | `ctrl+x` | composer.mode |
| `:` command_line | `shift+;` | commandPalette.toggle |
| `<M-p>` agent.model | `alt+p` | modelPicker.toggle |
| `<M-t>` agent.effort | `alt+t` | composer.effort |
| `<M-s>` agents.stack | `alt+s` | threadPanel.toggle |
| `<M-x>` voice.hold | `alt+x` | composer.dictation |

`alt+f` is deliberately left unbound: Graphide's `<M-f>` is fast mode, and T3
has no fast-mode command, so anything else on that key would fire the wrong
action under Ben's fingers. It used to hold `filePicker.toggle`.

Four chords were taken away rather than ported, because they had T3 commands
on keys vim needs for text and for panes:

| chord | had | why it went |
|---|---|---|
| `ctrl+h` | `workspace.focusPrevious` | the pane walk is the plugin's now, and `<C-h>` while typing is a backspace |
| `ctrl+l` | `workspace.focusNext` | the same, the other way |
| `ctrl+j` | `terminal.toggle` | Graphide's `<C-j>` is the pane below, not a toggle. `<C-S-;>` still toggles the terminal |
| `ctrl+k` | `terminal.toggle` | Graphide's `<C-k>` is the pane above |

`<C-w>`, `<C-u>` and `<C-h>` while typing were the worst of these: `mod+w`
closed the right panel, `mod+u` opened the usage page and `mod+h` stepped the
ring, so vim's three erasers all fired the app instead of editing the text.
The plugin takes all three in insert mode now.

## Graphide features T3 has no command for

Nothing can be bound to these. T3's bindable command list is fixed at 73 names
plus `script.<slug>.run`; there is no text-editing, LSP, graph or review
command in it. Listed so nobody spends a second afternoon looking.

| Graphide | What it does | Nearest T3 thing |
|---|---|---|
| `<M-f>` agent.fast | fast mode on or off | none |
| `<C-,>` settings (normal mode) | the settings page | none, no settings command |
| `<F10>` menu.app | the app menu | none |
| `K` code.hover | what the language server says | none, no LSP |
| `<C-a>` ask | ask with the selection | none |
| `<C-^>` buffer.alternate | the buffer before this one | none, no MRU toggle |
| `gd gD grr gri grt grn gra` | definition, refs, rename, code actions | none, no LSP |
| `]d` `[d` `<leader>cd` | diagnostics | none |
| `<leader>q` `]q` `[q` | the attention walk, requests for you | none |
| `]a` `[a` | next/prev **running** agent | thread.next/previous, unfiltered |
| `<leader>m` view.graph | the graph | none |
| `<leader>T` view.tests | tests | none |
| `<leader>hs hr hS hR hu hb` | hunk accept, reject, undo, blame | diff.toggle only |
| `<leader><leader>` | the fuzzy agent picker | none. T3's command palette holds commands only, no threads, so this is left with no chord rather than opening something that cannot switch agents. `<leader>1` to `<leader>9` are the switch T3 can do |
| `<leader>sm sk sa sr ss s.` | marks, keymaps, transcripts, resume, pickers, recent | filePicker, projectSearch, commandPalette, chat.find only |
| `<leader>ds` `<leader>ws` | symbols here, symbols everywhere | none |
| `<leader>rn` `<leader>cf` | rename, format | none |
| `<leader>ar af ab aR ad aL` | restart, fork, bump, resume-limited, definition, launcher | none. `thread.fork` exists as an RPC but is not bindable |
| `<leader>tc tn tp tm tb` | chrome, engine, perf, motion, blame toggles | none |
| `<C-w>=` `<C-w>x` `<C-w>HJKL` `<C-w>> < + -` | equalize, exchange, move, resize | none: T3's panes are dragged, and no command moves or sizes one |
| the list's `n y A e V / f N . ! L x gd gb` | answering, selecting, filtering, marking a row | none; each says so on the message line |
| the row menu's archive, delete, snooze | taking an agent out of the list | menu items with no command behind them. `dd` settles instead, and `zz` and `dm` open the menu |

`<C-w>s` and `<C-w>v` reach `terminal.split` / `terminal.splitVertical`, the
only split T3 has. T3's own defaults guard those on `terminalFocus`, but the
sequence engine steps aside whenever the terminal has focus (so Ctrl+W still
deletes a word in a shell), so a `terminalFocus` guard could never hold at
dispatch time and the two keys were dead. They are bound on `terminalOpen`
instead: split the terminal if there is one. Graphide's `pane.split` splits any
pane, so this is narrower than Graphide either way.

## T3 features Graphide has no key for

These needed keys invented for them. They sit outside Graphide's trees on
purpose, so they never shadow a Graphide key.

* the browser pane: `preview.toggle` and its refresh, url, find and zoom
* the usage page: `usage.open`, cost/tokens/limits, the four periods
* worktrees and PRs: `composer.workspace`, `composer.branch`,
  `composer.previousWorktree`, `pullRequest.copyNumber`
* the queued-message flow: `thread.editQueuedMessage`,
  `thread.steerQueuedMessage`, `composer.sendAlternate`,
  `composer.sendBackground`, `composer.sendAndNewThread`, `composer.stash`
* `thread.settle`, `modelPicker.jump.1-9`, the provider walk,
  `editor.openFavorite`, `view.reopenClosed`, the theme trio
* `thread.jump.1-9` is the exception that earned a place in the tree:
  `<leader>1` to `<leader>9`. Graphide has no such key, but it is the only
  agent switch T3 can do in one stroke, and `<leader><leader>`, which would
  be the Graphide way, has nothing to point at.

## Rejected approaches, and why

**Patching T3's minified keybinding resolver to take sequences.** It is one
function (`utils-*.js`, the resolver exported to every call site), so it is
tempting. Rejected because the composer plugin already owns modal state and a
global keydown handler, so the tree can live there and reach T3 through its
own public binding layer instead. That keeps this package's rule of never
reading a minified symbol, which is what makes it survive T3 releases.

**A keyd or xremap leader daemon.** Would give the real `<Space>` tree in every
app and survive every T3 update, but an evdev-level daemon cannot see whether
a text box has focus, so `<Space>` would have to be window-class scoped or
tap-versus-hold. The renderer knows the focus and the mode for free.

**Flattening the leader tree to `ctrl+alt+<tail>`.** Keeps the last letter of
each Graphide sequence and needs no patch at all. Kept as the fallback if the
sequence engine ever has to be turned off: the chords in
`keybindings.json`'s dispatch block already are that flattening, and typing
them by hand works.
