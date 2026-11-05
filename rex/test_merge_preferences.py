"""Preference restore must preserve machine data and unrelated custom themes."""

import importlib.util
import datetime
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("merge-preferences.py")
spec = importlib.util.spec_from_file_location("merge_preferences", SCRIPT)
merger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merger)
THEMES = merger.THEMES


class PreferenceMergeTests(unittest.TestCase):
    def test_preserves_machine_keys_and_unrelated_themes(self):
        current = {"host": "this-mac", "font": "old", THEMES: json.dumps([
            {"id": "other", "name": "My theme"}, {"id": "saved", "name": "Old"}]).encode()}
        saved = {"font": "new", THEMES: b'[{"id":"saved","name":"New"}]'}
        merged = merger.merge_preferences(current, saved)
        self.assertEqual(merged["host"], "this-mac")
        self.assertEqual(merged["font"], "new")
        self.assertIsInstance(merged[THEMES], bytes)
        self.assertEqual(json.loads(merged[THEMES]), [
            {"id": "other", "name": "My theme"}, {"id": "saved", "name": "New"}])
        self.assertEqual(current["font"], "old")

    def test_preserves_saved_theme_bytes_when_no_other_themes_exist(self):
        saved = plistlib.loads(SCRIPT.with_name("macos-preferences.plist").read_bytes())
        merged = merger.merge_preferences(saved, saved)
        self.assertEqual(merged[THEMES], saved[THEMES])
        self.assertEqual(plistlib.loads(plistlib.dumps(merged)), saved)

    def test_string_encoded_themes_stay_strings(self):
        result = merger.merge_preferences(
            {THEMES: '[{"id":"local","name":"Żółty"}]'},
            {THEMES: '[{"id":"saved"}]'})
        self.assertIsInstance(result[THEMES], str)
        self.assertEqual(json.loads(result[THEMES])[0]["name"], "Żółty")

    def test_no_saved_themes_leaves_current_value_untouched(self):
        result = merger.merge_preferences({THEMES: b"existing-format"}, {"font": "new"})
        self.assertEqual(result[THEMES], b"existing-format")

    def test_malformed_or_duplicate_themes_abort(self):
        for invalid in (b"not json", b"{}", b'[{}]', b'[{"id":3}]',
                        b'[{"id":"same"},{"id":"same"}]'):
            for current, saved in (({THEMES: invalid}, {THEMES: b"[]"}),
                                   ({}, {THEMES: invalid})):
                with self.subTest(invalid=invalid, saved=saved):
                    with self.assertRaises(ValueError):
                        merger.merge_preferences(current, saved)

    def test_failed_merge_never_overwrites_output(self):
        with tempfile.TemporaryDirectory() as directory:
            current, saved, output = [Path(directory) / name for name in ("current", "saved", "output")]
            current.write_bytes(plistlib.dumps({THEMES: b"broken"}))
            saved.write_bytes(plistlib.dumps({THEMES: b"[]"}))
            output.write_bytes(b"keep me")
            result = subprocess.run([sys.executable, str(SCRIPT), str(current), str(saved), str(output)],
                                    text=True, capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Cannot merge Rex preferences", result.stderr)
            self.assertEqual(output.read_bytes(), b"keep me")

    def test_cli_preserves_fractional_machine_timestamps(self):
        with tempfile.TemporaryDirectory() as directory:
            current, saved, output = [Path(directory) / name for name in ("current", "saved", "output")]
            timestamp = datetime.datetime(2026, 11, 5, 22, 0, 1, 247956)
            machine = {"updated": timestamp, "activity": {"seen": timestamp}, "host": "this-mac"}
            current.write_bytes(plistlib.dumps(machine, fmt=plistlib.FMT_BINARY))
            saved.write_bytes(plistlib.dumps({"font": "new"}))
            subprocess.run([sys.executable, str(SCRIPT), str(current), str(saved), str(output)],
                           check=True, capture_output=True, timeout=10)
            self.assertEqual(plistlib.loads(output.read_bytes()), {**machine, "font": "new"})


if __name__ == "__main__":
    unittest.main()
