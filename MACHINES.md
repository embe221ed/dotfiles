# Machines

One row per machine that has, or ever had, a symlink into a `scripts` checkout.
A row is signed off only when 5.5.8's `find` returns EMPTY on that machine.

The `scripts clone` column is MANDATORY and must hold a real absolute path or
the word `none`. It is not bookkeeping: it is the address 5.5.8b re-keys nvim
sessions/zoxide against, and it is the ONLY route by which Phase 6's tombstones
reach a machine you are not sitting at — they arrive as a `git pull` into that
clone and by no other mechanism.

| Host | Role | OS | dotfiles clone | scripts clone | keeps scripts? why | frozen SHA | cut over | interdot? | zsh owner | 5.5.8 find output |
|---|---|---|---|---|---|---|---|---|---|---|
| gazorpazorp | **MAIN** | macOS 26.6 (25G72), Darwin 25.6.0, **x86_64** | /opt/dotfiles | **/opt/scripts** (HEAD 0586ee2, clean but for `?? configs/oh-my-zsh/completions/_rustup`) | **yes** — dev-container + CTF scripts (answer A2) | `0586ee2` | **2026-08-06** | **yes** — /opt/tools/interdotensional, pulled to `0f220ca` at 5.5.5a (9 link entries) | **the machine itself** — see below | **EMPTY** ✅ on `main` |
| krootabulon | VPS | Ubuntu 24.04 | /opt/dotfiles | /opt/scripts | yes — utils/, pwn/, the container image | n/a (cut over first) | **2026-08-06** | yes | this repo (`zsh/zshrc`, `zsh/zshenv`) | **EMPTY** ✅ |
| iPad (Blink) | — | iPadOS | none | none | n/a | n/a | n/a | n/a | n/a | no clone, no symlinks; depends on the VPS over ssh |

## gazorpazorp — symlink inventory and post-split owner

Seven symlinks pointed into `/opt/scripts` before the migration (0.5.1). The
Linux VPS had three, and only `~/.config/nvim` overlaps — which is why this
table exists per-machine and not once.

| Link | Was | Owner after the split |
|---|---|---|
| `~/.config/nvim` | `-> /opt/scripts/configs/nvim` | `install.sh` (core row) → `/opt/dotfiles/nvim` |
| `~/.config/silicon/config` | `-> …/configs/silicon/config` | `install.sh` Darwin row → `/opt/dotfiles/silicon/config` |
| `~/.oh-my-zsh/custom/themes/catppuccin.zsh-theme` | `-> …/configs/oh-my-zsh/catppuccin.zsh-theme` | `install.sh` Darwin row |
| `~/.oh-my-zsh/custom/themes/cyberpunk.zsh-theme` | `-> …/configs/oh-my-zsh/cyberpunk.zsh-theme` | `install.sh` Darwin row |
| `~/.config/ghostty` **(directory link)** | `-> …/configs/ghostty` | **DELETED in 5.5.5b.** `interdot link` then makes a real dir holding `config` |
| `~/.config/zellij` **(directory link)** | `-> …/configs/zellij` | **DELETED in 5.5.5b.** `interdot link` then makes a real dir holding `config.kdl` |
| `~/.config/kitty` **(directory link)** | `-> …/configs/kitty` | **DELETED in 5.5.5b, not replaced** — kitty is not installed here; the link was vestigial |

Owned by **interdotensional** on this machine, not by either repo, and unchanged
by the migration: `~/.tmux.conf`, `~/.config/colorls`,
`~/.oh-my-zsh/custom/interdot.zsh`, `~/.oh-my-zsh/custom/themes/theme.zsh-theme`,
`~/.ipython/profile_default/ipython_config.py`, plus `~/.config/ghostty/config`
and `~/.config/zellij/config.kdl` once 5.5.5b has run.

Also interdot's, but **renamed by the migration** — do not read these as
unchanged: `~/.config/nvim/lua/globals.lua` and `~/.config/nvim/lua/ui/colors.lua`
are committed symlinks today; 2.6 replaces each with a committed shim and moves
the generated file to `…/globals.generated.lua` and `…/ui/colors.generated.lua`,
which is what `interdot link` fills from 5.5.6 onward.

Absent here, recorded so nobody goes looking: **kitty** (not installed —
`~/.config/kitty` was vestigial) and **tmux-powerline** (nothing anywhere on the
machine, which is what makes answer A3 safe). `ghostty +show-config` resolves to
theme *Gruvbox Material Light*, font *Maple Mono*, and **no `custom-shader`
line** — confirming A4: the shaders were never active here either. There is a
0-byte file at `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`;
it is not ghostty's config path and is not the live config. Do not act on it.

## gazorpazorp — zsh is this machine's own. DECIDED; do not relitigate.

`~/.zshrc` (**14854 B**), `~/.zshenv` (**356 B**) and `~/.zprofile` (**358 B**)
are independent real files — not symlinks, not copies. This repo's are 10881 B
and 1672 B, and it ships no `zprofile` at all. They diverged long ago and were
then hand-synced in places: the Mac sets `ZSH_THEME=theme` (matching
`zsh/zshrc:25`) and its `$fpath` carries the exact path from `zsh/zshrc:52`.
`~/.zlogin` is absent. **`~/.zshrc.local` is absent**, so this repo's
machine-local escape hatch — the mechanism 5.5.7 tells you to use for the
`path_helper` fix — is entirely unexercised here and will be created for the
first time during the cutover.

**The repo's `zsh/` is scoped to the VPS and the dev container.** `install.sh`
does not link `~/.zshrc` or `~/.zshenv` on Darwin (4.1), and `rescue.sh` does not
touch them either (4.2). **Unifying the two is a tracked follow-up, not part of
this migration** — the byte sizes above are the diff to start from.

**What this machine still owns by hand:** the `$fpath` line in its own
`~/.zshrc`, rewritten in 5.5.5c from `/opt/scripts/configs/oh-my-zsh/completions`
to `${XDG_CONFIG_HOME:-$HOME/.config}/zsh/completions`. That is the one edit
`install.sh` cannot make, because it lives in a file this repo does not own.

## 5.5 completion log — 2026-08-06

Both machines cut over. Recorded here because two of these edits live in files
no repository owns, so this table is the only place they are written down.

| What | gazorpazorp (MAIN) | krootabulon (VPS) |
|---|---|---|
| `install.sh --force` | rc 0, `--check` rc 0 | rc 0, `--check` rc 0 |
| 5.5.5a — interdot pulled | `0f220ca`, **9** link entries | n/a (origin of the commit) |
| 5.5.5b — stale dir symlinks removed | `~/.config/{ghostty,zellij,kitty}` | n/a (never had them) |
| 5.5.5c — machine's own `~/.zshrc` | **edited by hand**; backup at `~/.zshrc.pre-split` | n/a (uses this repo's `zsh/zshrc`) |
| Residual `/opt/scripts` in own zsh files | **1, legitimate**: `export UTILS="/opt/scripts/utils"` — `utils/` stays in `scripts` forever and is why `determine_system.sh` resolves by name here | n/a |
| 5.5.8 — untracked `_rustup` cleared | yes, before the pull | n/a (2.1 committed it) |
| 5.5.8 — `find ~` for `scripts/configs` links | **EMPTY** | **EMPTY** |
| Branch after unfreeze | `main` | `main` |

`~/.zshrc.pre-split` (14854 B) stays until Phase 9.
