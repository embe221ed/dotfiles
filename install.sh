#!/bin/sh
# install.sh — link this repository into $HOME.
#
# POSIX sh. Works on Linux and macOS (BSD userland: no `readlink -f`).
# Named `install.sh` at the repo root on purpose: GitHub Codespaces and the
# VS Code Dev Containers extension probe for exactly this filename.
#
#   ./install.sh                 link everything (default profile: sui)
#   ./install.sh --lang aptos    use the aptos treesitter/LSP profile
#   ./install.sh --dry-run       print the plan, touch nothing
#   ./install.sh --check         verify an existing install, touch nothing
#   ./install.sh --force         move a real file/dir at a destination aside
#   ./install.sh --with-zsh      also link ~/.zshrc and ~/.zshenv on macOS
#                                (they are suppressed there by default — the Mac
#                                keeps its own; see MACHINES.md)
#
# The manifest is OS-CONDITIONAL, and macOS differs in BOTH directions.
#
#   Linux / container : 5 rows — ~/.zshenv, ~/.zshrc, ~/.config/nvim,
#                       ~/.config/zsh/completions, nvim/lua/languages.lua
#   macOS (default)   : the last 3 of those (the zsh pair is SUPPRESSED — see
#                       zsh_links) plus a 3-row Darwin tail: silicon/config and
#                       the two oh-my-zsh prompt themes. Up to 6.
#   macOS --with-zsh  : as above with the zsh pair restored. Up to 8.
#
# Every conditional row is gated on its consumer being present, so an absent
# consumer is a skipped row rather than an error, and every skip is PRINTED. The
# tail is not cosmetic: without it every Mac-only link is hand-made, which means
# `--check` cannot see it, `rescue.sh` cannot recreate it, and 5.5.8's `find`
# sign-off proves nothing about it.
#
# THE TAIL IS WRITTEN FROM THE 0.5.1 PROBE, NOT FROM GUESSES. All three rows an
# earlier draft carried here were wrong and are gone:
#   kitty   — NOT INSTALLED on the Mac. The ~/.config/kitty symlink found there
#             is vestigial; 5.5.5b deletes it rather than repointing it.
#   ipython — installed, but ~/.ipython/profile_default/ipython_config.py points
#             at interdotensional's output/ipython/, not at this repo. This
#             repo's ipython/ipython_config.py is consumed by NOTHING on either
#             machine (kept per decision 3; recorded as a follow-up candidate).
#   colorls — same story: ~/.config/colorls points at output/colorls on BOTH
#             machines. There is no double-ownership question to resolve, so the
#             warning the draft added here is deleted with the row.
#
# ghostty and zellij are deliberately ABSENT too: this repository ships no
# ghostty/ and no zellij/ directory, so there is nothing to link.
# ~/.config/ghostty/config and ~/.config/zellij/config.kdl are owned end-to-end
# by embe221ed/interdotensional's `interdot link` (general.yml, 2.6d).
#
# determine_system.sh is likewise NOT a manifest entry. It lives in
# embe221ed/scripts (utils/), next to display_mode.sh, and the two oh-my-zsh
# themes here resolve it by NAME with a `uname` floor that returns the identical
# string. Linking a copy into ~/.local/bin would buy a preference, not a
# correctness property, and would put a second copy of that file on disk.
#
# Exit status:
#   0  everything is in place (or, without --check, was put in place)
#   1  a source is missing, a destination is occupied, or a link failed
#   2  --check only: the links are fine, but a generated nvim slot is
#      missing or dangling (nvim will start, unthemed)
#
# The script is idempotent: re-running it is a no-op, so it is safe in a
# Dockerfile RUN layer. It never touches the network.

set -eu

PROG=install.sh
STAMP=$(date +%Y%m%d%H%M%S)

DRY_RUN=no
CHECK=no
FORCE=no
WITH_ZSH=no
LANG_PROFILE=sui

# ------------------------------------------------------------------- messaging
say()  { printf '%s\n' "$*"; }
plan() { printf '  %-9s %s\n' "$1" "$2"; }
warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }
err()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; N_ERR=$((N_ERR + 1)); }
die()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }

usage() {
	cat <<'USAGE'
usage: install.sh [--lang sui|aptos] [--dry-run] [--check] [--force]
                  [--with-zsh] [--help]

  --lang P    which nvim language profile to activate; creates
              nvim/lua/languages.lua -> languages.lua.P  (default: sui)
  --dry-run   print what would change and exit
  --check     verify an existing install and exit; also reports whether the
              two generated nvim slots are present (see README)
  --force     a destination that exists and is NOT a symlink is moved to
              <dest>.bak-<timestamp> instead of aborting
  --with-zsh  link ~/.zshrc and ~/.zshenv on macOS too. They are suppressed
              there by default: that machine keeps its own zsh configuration,
              which never was a copy of this one. No effect off macOS.
USAGE
}

while [ $# -gt 0 ]; do
	case $1 in
	--lang)
		[ $# -ge 2 ] || die "--lang needs an argument (sui or aptos)"
		LANG_PROFILE=$2
		shift 2
		;;
	--lang=*) LANG_PROFILE=${1#--lang=}; shift ;;
	--dry-run) DRY_RUN=yes; shift ;;
	--check)   CHECK=yes;   shift ;;
	--force)   FORCE=yes;   shift ;;
	--with-zsh) WITH_ZSH=yes; shift ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; die "unknown option: $1" ;;
	esac
done

case $LANG_PROFILE in
sui | aptos) ;;
*) die "unknown --lang profile: $LANG_PROFILE (expected sui or aptos)" ;;
esac

# --------------------------------------------------------------- self-location
# $DOTFILES is derived from where this script lives, so the repository contains
# no absolute path to itself and can be cloned anywhere, on any machine.
# CDPATH= so a user's CDPATH cannot make `cd` land somewhere else (or print).
case $0 in
*/*) self_dir=${0%/*} ;;
*)   self_dir=. ;;
esac
DOTFILES=$(CDPATH= cd -- "$self_dir" && pwd -P) ||
	die "cannot resolve my own directory from \"$0\" — run me as a file, not on stdin"
[ -f "$DOTFILES/$PROG" ] ||
	die "resolved DOTFILES=$DOTFILES but $DOTFILES/$PROG does not exist"

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}

# Note the `:-` semantics: these defaults apply only when the variable is UNSET.
# If you invoke this script with an overridden $HOME (the Phase 8.3 cold-clone
# test does exactly that) you MUST override the XDG variables too, or an
# ambient XDG_CONFIG_HOME will aim the run at your real ~/.config.

OS=$(uname)

# The zsh completions are being moved out of oh-my-zsh/ (they have nothing to do
# with oh-my-zsh; only $fpath). Accept either location so this script is correct
# before and after that `git mv`.
COMPLETIONS_SRC=$DOTFILES/zsh/completions
[ -d "$COMPLETIONS_SRC" ] || COMPLETIONS_SRC=$DOTFILES/oh-my-zsh/completions
COMPLETIONS_DST=$XDG_CONFIG_HOME/zsh/completions

# --------------------------------------------------------------------- helpers

# One level of indirection, and the *literal* target. Deliberately not
# `readlink -f`: BSD readlink has no -f, and resolving would defeat the identity
# check below. No `--`: readlink is not a POSIX utility and BSD's handling of
# `--` is not guaranteed; every path we pass is absolute or a literal filename.
link_target() { readlink "$1" 2>/dev/null || printf ''; }

# Where a manifest source actually lives. Absolute entries are used as-is;
# relative ones are resolved against the directory holding the link, which is
# what a relative symlink means.
src_path() {
	case $1 in
	/*) printf '%s' "$1" ;;
	*)  printf '%s/%s' "${2%/*}" "$1" ;;
	esac
}

# ok | retarget | conflict | create
#
# Note the order: -L before -e. `[ -e ]` follows symlinks, so a correct
# symlink-to-directory and a real directory are indistinguishable to it — which
# is exactly how `ln -sfn` silently nesting a link *inside* an existing real
# directory goes unnoticed. Identity is decided by comparing readlink output.
classify() {
	if [ -L "$2" ]; then
		if [ "$(link_target "$2")" = "$1" ]; then printf ok; else printf retarget; fi
	elif [ -e "$2" ]; then
		printf conflict
	else
		printf create
	fi
}

# The manifest, fed to a callback. A here-document (not a pipe) keeps the loop
# in the current shell, so the counters the callbacks bump survive. IFS is only
# '|', so spaces inside a path are preserved.

# The Darwin tail of the manifest.
#
# Emitted as ordinary manifest rows so they go through the same classify /
# preflight / apply / verify path as the core rows — that is the entire point:
# `--check` reports them, `--dry-run` plans them, `--force` backs up whatever
# real file a Mac already has at one of these destinations.
#
# Every row is gated on its consumer being present, so an absent consumer is a
# row that never exists rather than a "missing destination" error. `cmd && printf`
# is safe under `set -e`: -e is ignored for any command of an AND-OR list other
# than the last, and the explicit `return 0` keeps the function's own status
# clean. Verified under both dash and sh.
#
# ROW 1 — silicon. Gated on `command -v silicon`, because it is the one row here
# with a binary to gate on. The Mac reads this file today through
# ~/.config/silicon/config -> /opt/scripts/configs/silicon/config, which is why
# 2.9 no longer moves configs/silicon into utils/. silicon reads no config on a
# machine where the binary is absent, so a skipped row costs nothing. NOTE: the
# 0.5.1 probe did not test for `silicon`; if it is not installed on the Mac this
# row is skipped and `report_skipped` says so out loud.
#
# ROWS 2 and 3 — the two oh-my-zsh prompt themes. These are the only rows whose
# destination is NOT an XDG path: oh-my-zsh loads themes from
# $ZSH_CUSTOM/themes/, so the destination is derived as
# ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/ — the same default oh-my-zsh
# itself uses, and the same shape zshrc:56 already uses for $ZSH_CUSTOM/plugins.
# They are gated on that directory EXISTING rather than on a `command -v`,
# because "is oh-my-zsh installed" has no binary to ask; without the gate this
# script would mkdir -p an oh-my-zsh tree on a machine that has no oh-my-zsh.
#
# Both themes are DORMANT on the Mac — zshrc:25 sets ZSH_THEME="theme", so
# oh-my-zsh loads interdotensional's generated theme.zsh-theme and never sources
# either of these. Dormant is exactly why they need rows: they ARE linked
# (0.5.1 found both), nothing on the machine would ever complain if they broke,
# and after Phase 6 they would simply dangle forever.
#
# No kitty row: kitty is installed on NEITHER machine (0.5.1: ABSENT). The
# vestigial ~/.config/kitty directory symlink on the Mac is deleted by 5.5.5b,
# not managed here.
#
# No ipython or colorls row: on the Mac both of those destinations point at
# embe221ed/interdotensional's output/, not at this repo. Adding a row would
# start a fight this repo would lose and does not want.
#
# No ghostty and no zellij row: this repo has no ghostty/ or zellij/ directory to
# link (both held nothing but a generated symlink 2.3 removes). `interdot link`
# owns ~/.config/ghostty/config and ~/.config/zellij/config.kdl outright and
# creates the plain $HOME directories holding them.
OMZ_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

# The two zsh rows, suppressed on macOS unless --with-zsh.
#
# This is the only place in the manifest where an OS *removes* a row, so it is
# worth being explicit about why. The Mac's ~/.zshrc (14854 B), ~/.zshenv (356 B)
# and ~/.zprofile (358 B — this repo ships no zprofile at all) are independent
# real files that were never copies of this repo's zsh/zshrc (10881 B) and
# zsh/zshenv (1672 B). Linking over them would replace a working shell on the
# user's main machine to solve a problem nobody has. The repo's zsh/ is scoped to
# the Linux VPS and the dev container; unifying is a tracked follow-up.
#
# --with-zsh is the switch that follow-up flips. It exists so the suppression is
# a visible, planned, --dry-run-able row rather than a hole in the manifest.
zsh_links() {
	if [ "$OS" = Darwin ] && [ "$WITH_ZSH" = no ]; then
		return 0
	fi
	printf '%s|%s\n' "$DOTFILES/zsh/zshenv" "$HOME/.zshenv"
	printf '%s|%s\n' "$DOTFILES/zsh/zshrc"  "$HOME/.zshrc"
	return 0
}

# Same "say it out loud" rule as report_skipped: a suppressed row must never look
# like a row that simply is not there.
# Written as a plain `if`, not `[ A ] && [ B ] || plan …`: that idiom is correct
# here but it is the one every reader has to re-derive, and this file already
# spends its subtlety budget on `cmd && printf` inside darwin_links.
report_zsh_scope() {
	if [ "$OS" = Darwin ] && [ "$WITH_ZSH" = no ]; then
		plan "skip" "~/.zshrc and ~/.zshenv — macOS keeps its own (see MACHINES.md); --with-zsh overrides"
	fi
	return 0
}

darwin_links() {
	[ "$OS" = Darwin ] || return 0
	command -v silicon >/dev/null 2>&1 && printf '%s|%s\n' "$DOTFILES/silicon/config" "$XDG_CONFIG_HOME/silicon/config"
	if [ -d "$OMZ_CUSTOM" ]; then
		printf '%s|%s\n' "$DOTFILES/oh-my-zsh/catppuccin.zsh-theme" "$OMZ_CUSTOM/themes/catppuccin.zsh-theme"
		printf '%s|%s\n' "$DOTFILES/oh-my-zsh/cyberpunk.zsh-theme"  "$OMZ_CUSTOM/themes/cyberpunk.zsh-theme"
	fi
	return 0
}

# Say out loud which optional rows were skipped, so "silicon is not linked" and
# "silicon is not installed" are never the same silence. The oh-my-zsh pair is
# reported as one line, because they share one gate.
report_skipped() {
	[ "$OS" = Darwin ] || return 0
	command -v silicon >/dev/null 2>&1 ||
		plan "skip" "silicon not installed — no link managed for silicon/config"
	[ -d "$OMZ_CUSTOM" ] ||
		plan "skip" "no $OMZ_CUSTOM — the two oh-my-zsh themes are not linked"
	return 0
}

for_each_link() {
	_cb=$1
	while IFS='|' read -r _src _dst; do
		[ -n "${_src:-}" ] || continue
		"$_cb" "$_src" "$_dst"
	done <<EOF
$(zsh_links)
$DOTFILES/nvim|$XDG_CONFIG_HOME/nvim
$COMPLETIONS_SRC|$COMPLETIONS_DST
languages.lua.$LANG_PROFILE|$DOTFILES/nvim/lua/languages.lua
$(darwin_links)
EOF
}

# ------------------------------------------------------------- pre-flight pass
# Nothing is mutated until every source has been proven to exist and every
# destination has been proven absent-or-a-symlink. A half-migrated shell (a new
# ~/.zshenv pointing at a repo whose ~/.zshrc could not be linked) is much worse
# than not starting at all.
N_ERR=0
N_CHANGE=0
N_OK=0
COMPLETIONS_CHANGED=no

mark_changed() {
	N_CHANGE=$((N_CHANGE + 1))
	case $1 in "$COMPLETIONS_DST") COMPLETIONS_CHANGED=yes ;; esac
}

preflight() {
	_s=$1
	_d=$2
	_real=$(src_path "$_s" "$_d")

	if [ ! -e "$_real" ]; then
		err "missing source: $_real (needed by $_d)"
		return 0
	fi

	_parent=${_d%/*}
	if [ -e "$_parent" ] && [ ! -d "$_parent" ]; then
		err "cannot create $_d: $_parent exists and is not a directory"
		return 0
	fi

	case $(classify "$_s" "$_d") in
	ok)
		N_OK=$((N_OK + 1))
		plan "ok" "$_d"
		;;
	retarget)
		mark_changed "$_d"
		plan "retarget" "$_d  (currently -> $(link_target "$_d"))"
		;;
	create)
		mark_changed "$_d"
		plan "create" "$_d -> $_s"
		;;
	conflict)
		if [ "$FORCE" = yes ]; then
			mark_changed "$_d"
			plan "backup" "$_d -> $_d.bak-$STAMP, then link"
		else
			err "$_d exists and is not a symlink — move it aside yourself, or re-run with --force"
		fi
		;;
	esac
	return 0
}

# ------------------------------------------------------------------ apply pass
apply() {
	_s=$1
	_d=$2
	case $(classify "$_s" "$_d") in
	ok) return 0 ;;
	conflict)
		mv -- "$_d" "$_d.bak-$STAMP" || die "could not move $_d aside"
		say "backed up $_d -> $_d.bak-$STAMP"
		;;
	retarget)
		# rm, not `ln -sfn`: removing the link itself is unambiguous on both
		# GNU and BSD, and -n/-h behave differently enough to be worth avoiding.
		rm -f -- "$_d" || die "could not remove the existing symlink $_d"
		;;
	esac

	mkdir -p -- "${_d%/*}" || die "could not create the directory ${_d%/*}"
	ln -s -- "$_s" "$_d" || die "could not create the symlink $_d -> $_s"

	# Verify identity, not existence. If $_d had been a real directory, `ln`
	# would have created "$_d/$(basename $_s)" and `[ -e "$_d" ]` would still
	# pass — this is the check that catches it.
	[ "$(link_target "$_d")" = "$_s" ] ||
		die "link verification failed: $_d points at \"$(link_target "$_d")\", expected \"$_s\""
	[ -e "$_d" ] || die "dangling link: $_d -> $_s (the source vanished mid-run)"

	say "linked $_d -> $_s"
	return 0
}

# ------------------------------------------------------- generated nvim slots
# interdotensional's `interdot link` fills these with ABSOLUTE symlinks into its
# own output/ tree. If that repo moves or is absent the links dangle, the
# committed shims fall back to their defaults, and nvim starts unthemed with no
# error anywhere — silent degradation this check exists to make loud.
GEN_BAD=0

gen_slot() {
	# -e follows the link, so a dangling absolute link fails it. That is the
	# whole point: `test -e`, then -L to tell "absent" from "broken".
	if [ -e "$1" ]; then
		plan "ok" "$1"
	elif [ -L "$1" ]; then
		plan "DANGLING" "$1 -> $(link_target "$1")"
		GEN_BAD=$((GEN_BAD + 1))
	else
		plan "absent" "$1"
		GEN_BAD=$((GEN_BAD + 1))
	fi
	return 0
}

check_generated() {
	gen_slot "$XDG_CONFIG_HOME/nvim/lua/globals.generated.lua"
	gen_slot "$XDG_CONFIG_HOME/nvim/lua/ui/colors.generated.lua"
}

# ------------------------------------------------- determine_system self-test
#
# KEPT, but demoted from a gate to a probe — and this is the interesting design
# decision in this script, so it is worth the paragraph.
#
# determine_system.sh is NOT installed by this repository (it lives in
# embe221ed/scripts). "Absent" is a PERFECTLY VALID state — a cold clone, or any
# machine with no scripts checkout on PATH — and the two oh-my-zsh themes then
# fall back to `uname`, which returns the byte-identical answer. A check that
# failed on absence would fail on a supported configuration, so absence is
# reported and returns 0.
#
# It is NOT, however, the common case, and an earlier draft of this comment said
# so wrongly. Measured: /opt/scripts/utils is on PATH inside the dev container
# (devContainer.dockerfile:224) AND on the macOS machine (0.5.1's PATH dump), and
# is NOT on the Linux VPS's. So the script resolves on two of the three real
# machines and the floor is the fallback, not the norm.
#
# What is worth checking, and is the ONLY failure the `uname` floor cannot save
# you from, is a STALE script that IS resolvable: an older copy treats --print as
# no-args, prints nothing and exits 1 on Darwin. The theme's `[ -z "${SYSTEM}" ]`
# re-check catches it, but a silent stale copy on PATH is still something you
# want to hear about — and because the two machines where it resolves are exactly
# the two that carry a whole /opt/scripts/utils, that case is reachable on both.
# So: found-and-wrong is an error; not-found is information.
#
# Resolution order is deliberately IDENTICAL to the themes' block. Anything else
# and this function would be testing a different thing from the one that runs.
#
# `rc=0; "$ds" || rc=$?` is not stylistic: the naive `"$ds"; rc=$?` ABORTS under
# `set -e` on macOS, because the correct Darwin answer IS exit 1.
check_determine_system() {
	ds="${DETERMINE_SYSTEM:-}"
	[ -n "$ds" ] || { ds=$(command -v determine_system.sh 2>/dev/null) || ds=""; }
	if [ ! -x "$ds" ]; then
		plan "info" "determine_system.sh not resolvable — the oh-my-zsh themes use the \`uname\` floor (expected unless embe221ed/scripts is on PATH)"
		return 0
	fi
	p=$("$ds" --print 2>/dev/null) || p=""
	[ -n "$p" ] || { warn "$ds is STALE: --print printed nothing. Update embe221ed/scripts."; return 1; }
	[ "$p" = "$(uname)" ] || { warn "$ds --print said '$p', uname says '$(uname)'"; return 1; }
	rc=0; "$ds" || rc=$?
	case "$p" in Linux) want=0 ;; Darwin) want=1 ;; CYGWIN*|MINGW*|MSYS*) want=2 ;; *) want=3 ;; esac
	[ "$rc" = "$want" ] || { warn "$ds exit code $rc, expected $want for $p"; return 1; }
	say "$PROG: determine_system.sh ok ($ds -> $p, exit $rc)"
	return 0
}

# ---------------------------------------------------------------------- driver
MODE=install
[ "$DRY_RUN" = no ] || MODE="dry-run (nothing will be changed)"
[ "$CHECK" = no ] || MODE="check (nothing will be changed)"

say "$PROG: DOTFILES=$DOTFILES  profile=$LANG_PROFILE  os=$OS  mode=$MODE"
say ""
for_each_link preflight
report_zsh_scope
report_skipped

if [ "$N_ERR" -gt 0 ]; then
	say ""
	die "$N_ERR problem(s) found — nothing was changed"
fi

if [ "$CHECK" = yes ]; then
	say ""
	say "generated nvim slots (optional, produced by \`interdot link\`):"
	check_generated
	say ""
	DS_BAD=0
	check_determine_system || DS_BAD=1
	say ""
	if [ "$N_CHANGE" -gt 0 ]; then
		die "$N_CHANGE link(s) are not in place — run $PROG to fix"
	fi
	# Only ever set by a determine_system.sh that RESOLVED and then answered
	# wrong. An absent one is fine and returns 0 above.
	[ "$DS_BAD" = 0 ] || die "a stale/incorrect determine_system.sh is on PATH"
	if [ "$GEN_BAD" -gt 0 ]; then
		warn "$GEN_BAD generated nvim slot(s) missing or dangling; nvim will start unthemed"
		exit 2
	fi
	say "$PROG: all $N_OK links in place"
	exit 0
fi

if [ "$DRY_RUN" = yes ]; then
	say ""
	say "$PROG: --dry-run, nothing changed ($N_CHANGE would change, $N_OK already correct)"
	exit 0
fi

if [ "$N_CHANGE" -eq 0 ]; then
	say ""
	say "$PROG: already up to date ($N_OK links)"
	check_determine_system || warn "a stale determine_system.sh is on PATH (the themes' \`uname\` floor still answers correctly)"
	exit 0
fi

say ""
for_each_link apply

# zsh caches the completion functions it found on $fpath. Moving or creating the
# completions directory without dropping the dump means the new completions are
# invisible until the cache happens to expire.
if [ "$COMPLETIONS_CHANGED" = yes ]; then
	rm -f -- "$XDG_CACHE_HOME"/zsh/.zcompdump-* "$HOME"/.zcompdump*
	say "invalidated the zsh completion dump ($XDG_CACHE_HOME/zsh/.zcompdump-*)"
fi

say ""
check_determine_system || warn "a stale determine_system.sh is on PATH (the themes' \`uname\` floor still answers correctly)"
say "$PROG: done. Open a new shell, or \`exec zsh\`."
