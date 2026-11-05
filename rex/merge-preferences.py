#!/usr/bin/env python3
"""Merge the saved Rex preferences without deleting other custom themes."""

import json
import plistlib
import sys
from pathlib import Path


THEMES = "Workspace.customThemes"


def read_themes(value):
    themes = json.loads(value)
    if not isinstance(themes, list) or any(
            not isinstance(theme, dict) or not isinstance(theme.get("id"), str)
            for theme in themes):
        raise ValueError("Rex custom themes must be a JSON array of objects with string IDs")
    if len({theme["id"] for theme in themes}) != len(themes):
        raise ValueError("Rex custom themes contain duplicate IDs")
    return themes


def merge_preferences(current, saved):
    merged = {**current, **saved}
    if THEMES in saved:
        incoming = read_themes(saved[THEMES])
        existing = read_themes(current[THEMES]) if THEMES in current else []
        incoming_ids = {theme["id"] for theme in incoming}
        retained = [theme for theme in existing if theme["id"] not in incoming_ids]
        if retained:
            encoded = json.dumps(retained + incoming, ensure_ascii=False, separators=(",", ":"))
            merged[THEMES] = encoded.encode("utf-8") if isinstance(saved[THEMES], bytes) else encoded
    return merged


def main():
    if len(sys.argv) != 4:
        raise ValueError("usage: merge-preferences.py CURRENT.plist SAVED.plist OUTPUT.plist")
    current = plistlib.loads(Path(sys.argv[1]).read_bytes())
    saved = plistlib.loads(Path(sys.argv[2]).read_bytes())
    merged = merge_preferences(current, saved)
    # plistlib's XML writer truncates dates to whole seconds. Binary plists are
    # accepted by defaults import and preserve existing activity timestamps.
    Path(sys.argv[3]).write_bytes(plistlib.dumps(merged, fmt=plistlib.FMT_BINARY))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException) as error:
        sys.exit(f"Cannot merge Rex preferences: {error}")
