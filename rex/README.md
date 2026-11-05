# Rex

Tmux-style keys with Rex's native panes, floating terminals, scrollback, and
Interdimux navigation. A Rex **window** is a **tab inside a session**.
Press and release **Ctrl+b**, then press the next key.

## Everyday keys

| After Ctrl+b | Action |
| --- | --- |
| `c` | New tab |
| `1`…`9` | Select that tab in this session; absent numbers do nothing |
| `n` / `p` | Next / previous tab, wrapping within this session |
| `\|` / `-` | Split right / down |
| `h` / `j` / `k` / `l` | Focus left / down / up / right |
| `Ctrl+h/j/k/l` or `H/J/K/L` | Resize in that direction |
| `Alt+h/j/k/l` | Move the pane in that direction |
| `Enter` | Persistent pane mode: repeat the same movement keys |
| `z` / `=` | Toggle zoom / balance splits |
| `o` | Focus the next pane |
| `*` | New independent floating shell, inheriting the current directory |
| `d` | Float / dock the current pane |
| `m` | Hide / restore all floats in this tab |
| `,` / `r` / `$` | Rename tab / pane / session |
| `!` | Move the pane to a new tab |
| `[` / `/` | Browse history / search scrollback |
| `f` or `w` | Interdimux fuzzy session/tab/pane picker |
| `g` | Interdimux dashboard |
| `e` / `Tab` | Agents needing attention / next waiting agent |
| `a` | Native actions menu; choose a displayed key |
| `?` | Search all actions in Rex's command palette |
| `Ctrl+b` | Send one literal Ctrl+b to the terminal |
| `Escape` | Cancel a pending prefix |

Without a prefix: **Alt+p** toggles the scratch terminal, **F12** toggles
nested-tmux prefix passthrough, and **Shift+PageUp/PageDown** scroll history.
Native Cmd shortcuts remain available, including Cmd+Shift+P for the palette.

On this Mac, **left Option sends Alt; right Option composes characters**.
This lets terminal applications receive Alt shortcuts while keeping accented
characters available. Configure it under Settings → Terminal → Keyboard →
Option key. Rex's Automatic setting depends on the keyboard layout and can
produce characters such as `√` instead of Alt+V.

## Pane mode, history, and scratch

**Pane mode:** Ctrl+b, Enter. `h/j/k/l` focus, `H/J/K/L` or `Ctrl+h/j/k/l`
resize, and `Alt+h/j/k/l` move panes. `z` zooms, `=` balances, and `d`
floats/docks. The modifiers mean the same thing as after the prefix.
Resize steps are 2% of the split. Moving a tiled pane rearranges the layout;
moving a float changes its position.

Rex's **Autobalance splits** can override ratios requested by the CLI when
panes open or close. For tmux-style size preservation, turn it off under
Settings → Interface → Splits & Focus; use prefix+`=` to balance explicitly.
This remains a manual follow-up on this Mac: the review reproduced the ratio
override, but UI access became unavailable before that setting could be changed
and tested. See the [Rex setting](https://www.superlogical.com/rex/docs/reference/mac-settings#setting-splits-focus-autobalance-splits).

**History mode:** Ctrl+b, `[`. `k` / `j`, PageUp / PageDown, or Ctrl+u / Ctrl+d
scroll by pages. `K` / `J` jump between shell prompts when shell integration
provides them. `n` / `N` repeat the current search. `/` leaves the mode and
opens Find; `y` copies an existing mouse selection and leaves the mode.
This is native scrollback browsing, not vi selection or tmux copy-mode.

Both modes ignore unbound keys. **q, Escape, Enter, Ctrl+c, or F12** leave
the complete mode stack, including a parent actions menu. Normal typing
resumes afterward. There is no timed tmux repeat window; use pane mode for
repeated resizing.

**Scratch:** Alt+p creates one shell per tab in the originating pane's directory.
Press it from another pane to bring that shell forward; press it inside the
scratch to hide it. The process, directory, and scrollback survive hiding.
If opened from a zoomed pane, hiding it restores that pane's zoom. The return
zoom is transient and resets on a config reload; the shell itself survives.
Closing the scratch lets the next Alt+p create a fresh one. Keep its reserved
`scratch` label and single-pane floating layout to retain toggle behavior;
renaming, docking, or splitting it releases it from the scratch shortcut.
`*` always creates a separate ordinary floating shell.

**Actions menu:** Ctrl+b, `a`. The menu shows native hints, uses the same
mnemonics as the direct shortcuts, and closes after a choice. `p` opens scratch,
`m` enters pane mode, and `[` enters history mode. **q or Escape** cancels.
Unbound keys are ignored. The two submenus open directly in the client;
other choices stay guarded until their server callback returns, then close
the menu before opening a prompt or performing the native operation.

**Nested tmux:** F12 forwards Ctrl+b directly to the terminal. Escape also
passes through. F12 again restores Rex's prefix. In pane/history mode, the
first F12 leaves that mode; a second enables passthrough.

Rex spells shifted keys using their unshifted forms: `|` is `shift+\`, `*` is
`shift+8`, `$` is `shift+4`, and `?` is `shift+/` on this keyboard layout.
Native hint styling and grouping are app-controlled. Show key sequence hints
is enabled under Settings → Terminal → Keyboard.

## Install and reload

From the repository root:

```sh
./install.sh --dry-run
./install.sh
rex config check
rex config reload
rex client ls
rex -C LABEL_OR_ID do client.config.reload
python3 rex/check-bindings.py
```

The installer links `init.lua` into `${XDG_CONFIG_HOME:-$HOME/.config}/rex/`
when Rex is installed. On macOS it also links the bundled CLI to
`~/.local/bin/rex` if no CLI resolves elsewhere on PATH. `rescue.sh` supports
both links. Other files in the Rex config directory stay local.

Reload both server and app after edits; a server-only reload can leave the
app's shortcut cache stale. **Reload Config** in the app's palette also refreshes
the app. Native floating-shell, rename, and scrolling actions require Mac
preview.26/build 1829 or newer; the validator checks the connected app's actual
capabilities. No server restart is needed for this configuration.

## Interdimux

The optional integration lives at `/opt/tools/interdimux/integrations/rex.lua`.
Build its Rust navigator with:

```sh
cargo build --manifest-path /opt/tools/interdimux/rust/Cargo.toml --release --locked
```

The picker uses fzf 0.74+. Enter selects; Escape/Ctrl+c closes. Ctrl+g opens
its actions, Ctrl+/ toggles preview, Ctrl+r reloads, and Ctrl+] changes search
scope. The dashboard on prefix+g exposes navigation, rename/close/swap/zoom,
project creation, waiting agents, scheduled sends, jobs, and health checks.
Type `imux` in Rex's command palette to find its named actions.

`INTERDIMUX_ROOT` selects another checkout; an empty value uses the default.
`INTERDIMUX_BIN`, `INTERDIMUX_FZF_BIN`, and `INTERDIMUX_REX_BIN` override the
navigator, fzf, and coordinator CLI paths. These variables must be visible
to Rex's server. Reload after integration edits too.

If the integration is missing or setup fails, the core configuration still
loads. Prefix+f/w opens Rex's native Go to Anything; g opens the command
palette; e/Tab toggles native Activity. Partial integration bindings are removed
on failure. The integration reports missing runtime dependencies when invoked.

See the [shared Interdimux plan](INTERDIMUX-PLAN.md) and the integration
checkout for its detailed workflows. This configuration selects terminal
dashboard presentation and the Ctrl+b, Tab attention shortcut.

## Verification

```sh
python3 -B -m unittest discover -s rex -p 'test_*.py' -v
lua rex/test-config.lua
rex config check
rex config reload
rex -C LABEL_OR_ID do client.config.reload
python3 rex/check-bindings.py --client LABEL_OR_ID
sh -n rex/restore-macos-preferences.sh
```

The offline suite tests the real Lua config with a Rex API double: origin
resolution including floats, window wrapping/numbers, stale contexts, scratch
reuse/cwd/zoom/errors, menu ordering, and optional-integration failures. It also
tests stale config detection, argument validation, and safe preference merging.
Lua 5.2+ is required for the behavior suite; the Python runner reports a skip
if Lua is unavailable.

The live validator checks action names, supported argument schemas, duplicate
keys, sequence conflicts, critical bindings and exits, exclusive modes, and the
loaded entry-file hash. It finds the bundled CLI if needed; `--rex PATH`
overrides it. Included Lua files and shortcuts saved in app settings are outside
the hash check, so reload and test those in the app.

For a keyboard smoke test, use a disposable session: verify numbered tabs and
wraparound, enter/leave both modes, search known scrollback text, toggle scratch
from a zoomed pane, and check literal-prefix/F12 forwarding in an inner tmux.
Use a raw key recorder when testing for input leaking through modes.

## Saved macOS preferences

`macos-preferences.plist` contains portable appearance and behavior settings,
including Maple Mono Light 16 pt, Symbols Nerd Font Mono fallback, Gruvbox
Material Dark, pane headers/borders, smooth scrolling, and left Option as Alt.
Session history, window positions, host identity, updater state, and the
generated `~/.config/rex/ssh_config` stay machine-local.

On another Mac, open Rex once, quit it, then run:

```sh
./rex/restore-macos-preferences.sh
```

The Python-backed restore saves a backup under
`~/Library/Preferences/rex-dotfiles-backup.XXXXXX/before.plist`, preserves other
machine preferences and unrelated custom themes, and replaces saved themes by
ID. Invalid or duplicate theme data aborts before import. The installer does
not import preferences automatically.

References: [configuration](https://www.superlogical.com/rex/docs/customize/config),
[key modes](https://www.superlogical.com/rex/docs/customize/key-modes),
[keyboard shortcuts](https://www.superlogical.com/rex/docs/customize/keyboard-shortcuts),
[Mac settings](https://www.superlogical.com/rex/docs/reference/mac-settings).
