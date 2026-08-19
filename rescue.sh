#!/bin/sh
# rescue.sh — repoint the host links at a chosen root.
#
#   ./rescue.sh              point everything at THIS checkout
#   ./rescue.sh --to <root>  point everything at <root> instead
#
# The --to form is what walks a machine BACKWARDS: it restores the pre-split
# layout from a repo that is not the pre-split repo, because the old tree has the
# same relative shape (zsh/zshrc, zsh/zshenv, nvim):
#
#   /opt/dotfiles/rescue.sh --to /opt/scripts/configs
#
# Before the completions move the old path was oh-my-zsh/completions, so that one
# link is best-effort: it tries both and warns rather than failing the run.
# The git aliases link (git/aliases.gitconfig) is best-effort too, gated on the
# root carrying the file: pre-split roots have no git/ directory at all, so
# there it is a silent skip, not a warning. The include.path line that reads the
# link lives in ~/.gitconfig — a per-machine file this script never touches — so
# repointing the symlink is the whole job.
#
# ON macOS IT DOES NOT TOUCH ~/.zshrc OR ~/.zshenv, and that is the single most
# important line in this file. Those are 14854 B and 356 B of INDEPENDENT,
# hand-maintained configuration on that machine — never copies of this repo's —
# and the `rm -f` two functions down does not ask. A "rescue" that silently
# deleted the main machine's shell config would be the worst outcome this whole
# migration can produce, and it would happen at the exact moment the user was
# already panicking. --with-zsh opts in, matching install.sh's flag of the same
# name; use it only after the zsh-unification follow-up lands.
#
# It also creates nvim/lua/languages.lua if the chosen root has none. That file
# is gitignored, so a fresh clone never has it, and init.lua:15 is an UNGUARDED
# `require('languages')` — without this, "rescue" hands you a working shell and
# an nvim that hard-errors on every start.
#
# On Darwin it additionally repoints silicon/config and the two oh-my-zsh prompt
# themes when the root has them, so a rescued Mac matches what install.sh would
# have built. There is no kitty row (kitty is installed on neither machine), and
# no ghostty or zellij equivalent: this repo ships no ghostty/ and no zellij/
# directory — those configs are owned end-to-end by embe221ed/interdotensional.
#
# WHAT THIS CANNOT DO: help a machine whose dotfiles clone is itself bad or
# absent — it lives inside that clone. That is `zsh -f` plus a fresh clone.
# POSIX sh, ln/mkdir/rm/readlink/printf only: a dangling ~/.zshenv means
# ~/.local/bin is off PATH, so nothing installed there may be used here.
set -eu

case $0 in */*) d=${0%/*} ;; *) d=. ;; esac
ROOT=$(CDPATH= cd -- "$d" && pwd -P)
WITH_ZSH=no
while [ $# -gt 0 ]; do
	case $1 in
	--to)
		[ $# -ge 2 ] || { echo "rescue.sh: --to needs a path" >&2; exit 1; }
		ROOT=$(CDPATH= cd -- "$2" && pwd -P); shift 2 ;;
	--with-zsh) WITH_ZSH=yes; shift ;;
	*) echo "rescue.sh: unknown option: $1" >&2; exit 1 ;;
	esac
done
XDG=${XDG_CONFIG_HOME:-$HOME/.config}
OMZ_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
OS=$(uname)

link() {
	[ -e "$1" ] || { echo "rescue.sh: no source $1 — skipped" >&2; return 0; }
	mkdir -p -- "${2%/*}"
	# A destination that is NOT a symlink is somebody's real data. `rm -f` would
	# delete a real file outright (no backup) and FAIL on a real directory, which
	# under `set -e` aborts the whole run half-migrated. Move it aside instead —
	# install.sh classifies this same case as a conflict rather than clobbering.
	if [ -e "$2" ] && [ ! -L "$2" ]; then
		_bak="$2.bak-$(date +%Y%m%d%H%M%S)"
		mv -- "$2" "$_bak" || {
			echo "rescue.sh: $2 exists and is not a symlink, could not move it aside — skipped" >&2
			return 0
		}
		echo "rescue.sh: moved $2 aside to $_bak" >&2
	fi
	rm -f -- "$2"
	ln -s -- "$1" "$2"
	[ "$(readlink "$2")" = "$1" ] || { echo "rescue.sh: $2 did not take" >&2; return 1; }
	echo "rescue.sh: $2 -> $1"
}

echo "rescue.sh: pointing at $ROOT"
# The zsh pair, scoped exactly as install.sh scopes it. Never silently: a machine
# whose shell this script declined to touch must SAY so, or the next thing the
# operator does is wonder why the rescue "did not take".
if [ "$OS" = Darwin ] && [ "$WITH_ZSH" = no ]; then
	echo "rescue.sh: macOS — leaving ~/.zshrc and ~/.zshenv ALONE (they are this" >&2
	echo "rescue.sh: machine's own, not this repo's). Pass --with-zsh to override." >&2
else
	link "$ROOT/zsh/zshenv" "$HOME/.zshenv"
	link "$ROOT/zsh/zshrc"  "$HOME/.zshrc"
fi
link "$ROOT/nvim"       "$XDG/nvim"
if [ -d "$ROOT/zsh/completions" ]; then
	link "$ROOT/zsh/completions" "$XDG/zsh/completions"
elif [ -d "$ROOT/oh-my-zsh/completions" ]; then
	link "$ROOT/oh-my-zsh/completions" "$XDG/zsh/completions"
else
	echo "rescue.sh: no completions directory under $ROOT — skipped" >&2
fi

# The shared git aliases. Same failing-AND-OR-list idiom as the Darwin block
# below (safe under `set -e`; see the comment there). Gated rather than warned:
# a --to root from before the split simply has no git/ directory, and a rescue
# is not the moment to hear about aliases.
[ -f "$ROOT/git/aliases.gitconfig" ] && link "$ROOT/git/aliases.gitconfig" "$XDG/git/aliases.gitconfig"

# languages.lua is gitignored, so a fresh clone has none and init.lua:15's
# unguarded require('languages') aborts the rest of init.lua. Relative link, to
# a sibling inside the same tree, so it stays correct if the tree moves. Never
# clobbers an existing choice — including an aptos one.
if [ ! -e "$ROOT/nvim/lua/languages.lua" ] && [ -e "$ROOT/nvim/lua/languages.lua.sui" ]; then
	ln -s languages.lua.sui "$ROOT/nvim/lua/languages.lua" &&
		echo "rescue.sh: $ROOT/nvim/lua/languages.lua -> languages.lua.sui" ||
		echo "rescue.sh: could not create languages.lua (read-only tree?)" >&2
fi

# Darwin extras, best effort: only when the root actually carries them, and only
# into a $ZSH_CUSTOM that already exists. A failing AND-OR list does NOT trip
# `set -e` (the failing command is not the list's last) — verified under sh, dash
# and bash. Mirrors install.sh's darwin_links() row for row; if you edit one,
# edit the other, because 5.5.8's `find` sign-off is written against both.
if [ "$OS" = Darwin ]; then
	[ -f "$ROOT/silicon/config" ] && link "$ROOT/silicon/config" "$XDG/silicon/config"
	if [ -d "$OMZ_CUSTOM" ]; then
		[ -f "$ROOT/oh-my-zsh/catppuccin.zsh-theme" ] &&
			link "$ROOT/oh-my-zsh/catppuccin.zsh-theme" "$OMZ_CUSTOM/themes/catppuccin.zsh-theme"
		[ -f "$ROOT/oh-my-zsh/cyberpunk.zsh-theme" ] &&
			link "$ROOT/oh-my-zsh/cyberpunk.zsh-theme" "$OMZ_CUSTOM/themes/cyberpunk.zsh-theme"
	fi
fi

# What must resolve at the end. The zsh pair is only asserted where this script
# is allowed to manage it — on a default macOS run those two files are the
# machine's own and their state is none of this script's business.
rc=0
if [ "$OS" = Darwin ] && [ "$WITH_ZSH" = no ]; then
	_must="$XDG/nvim"
else
	_must="$HOME/.zshenv $HOME/.zshrc $XDG/nvim"
fi
for l in $_must; do
	[ -e "$l" ] || { echo "RESCUE FAILED: $l does not resolve" >&2; rc=1; }
done
# nvim's hard dependency, checked THROUGH the link that was just made.
[ -e "$XDG/nvim/lua/languages.lua" ] ||
	{ echo "RESCUE WARNING: $XDG/nvim/lua/languages.lua does not resolve — nvim will error at init.lua:15" >&2; }
[ "$rc" = 0 ] && echo "rescue.sh: ok"
exit "$rc"
