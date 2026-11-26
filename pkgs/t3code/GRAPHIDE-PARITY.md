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
| T3's app chrome | `~/.t3/userdata/keybindings.json` | no, one chord per binding | no |
| T3's composer | `vim-composer.js` in this directory | yes, it owns them | yes |
| Claude Code's TUI | `~/.claude/keybindings.json` | yes, space separated | per context |

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
| `<C-h>` / `<C-l>` pane left/right | `ctrl+h` / `ctrl+l` | workspace.focusPrevious / focusNext |
| `<C-j>` / `<C-k>` pane down/up | `ctrl+j` / `ctrl+k` | terminal.toggle, down into it and back up |
| `<C-o>` / `<C-i>` jump back/forward | `ctrl+o` / `ctrl+i` | navigation.back / forward |
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
| `<leader>sm sk sa sp sr ss s.` | marks, keymaps, transcripts, projects, resume, pickers, recent | filePicker, projectSearch, commandPalette, chat.find only |
| `<leader>ds` `<leader>ws` | symbols here, symbols everywhere | none |
| `<leader>rn` `<leader>cf` | rename, format | none |
| `<leader>ar af ab aR ad aL` | restart, fork, bump, resume-limited, definition, launcher | none. `thread.fork` exists as an RPC but is not bindable |
| `<leader>tc tn tp tm tb` | chrome, engine, perf, motion, blame toggles | none |
| `<C-w>` move, resize, exchange, equalize, only | window management | split, splitVertical, close, and only for terminals |

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
* `thread.settle`, `thread.jump.1-9`, `modelPicker.jump.1-9`, the provider
  walk, `editor.openFavorite`, `view.reopenClosed`, the theme trio

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
