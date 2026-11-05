#!/bin/sh
# Restore the saved Rex UI preferences, retaining this machine's other keys.
set -eu

[ "$(uname)" = Darwin ] || { echo "This script is for macOS." >&2; exit 1; }
if pgrep -x Rex >/dev/null 2>&1; then
	echo "Quit Rex before restoring its preferences, then run this script again." >&2
	exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 1; }

case $0 in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
script_dir=$(CDPATH='' cd -- "$script_dir" && pwd -P)
domain=com.superlogical.rex
backup_dir=$(mktemp -d "$HOME/Library/Preferences/rex-dotfiles-backup.XXXXXX")

# Require an existing domain: on a fresh Mac, open Rex once and quit first.
if ! defaults export "$domain" "$backup_dir/before.plist"; then
	echo "Open Rex once and quit it before restoring these settings." >&2
	exit 1
fi

python3 "$script_dir/merge-preferences.py" "$backup_dir/before.plist" \
	"$script_dir/macos-preferences.plist" "$backup_dir/merged.plist"

defaults import "$domain" "$backup_dir/merged.plist"
printf 'Restored Rex preferences. Backup: %s\n' "$backup_dir/before.plist"
