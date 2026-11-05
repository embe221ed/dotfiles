"""Regression checks for failures that config parsing alone cannot catch."""

import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location(
    "check_bindings", Path(__file__).with_name("check-bindings.py"))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class LoadedConfigTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "init.lua"
        self.path.write_text('rex.bind("ctrl+b>c", "client.tab.new")\n')
        self.checked = {"path": str(self.path), "exists": True}
        self.keymap = {"config": {
            **self.checked, "hash": hashlib.sha256(self.path.read_bytes()).hexdigest(),
        }}

    def test_edit_with_unchanged_binding_count_is_stale(self):
        self.assertEqual(checker.validate_loaded_config(self.checked, self.keymap), [])
        self.path.write_text('rex.bind("ctrl+b>n", "client.tab.new")\n')
        self.assertIn("changed since", checker.validate_loaded_config(
            self.checked, self.keymap)[0])

    def test_missing_file_does_not_validate_old_keymap(self):
        self.path.unlink()
        self.checked["exists"] = False
        self.assertIn("missing", checker.validate_loaded_config(
            self.checked, self.keymap)[0])

    def test_another_config_path_is_not_fresh(self):
        self.keymap["config"]["path"] += ".other"
        self.assertIn("not the server", checker.validate_loaded_config(
            self.checked, self.keymap)[0])

    def test_older_server_cannot_claim_freshness(self):
        del self.keymap["config"]["hash"]
        self.assertIn("cannot verify", checker.validate_loaded_config(
            self.checked, self.keymap)[0])


class ArgumentTests(unittest.TestCase):
    def test_numeric_bounds_include_upper_limits(self):
        for bound, invalid, valid in [
                ("minimum", 0, 1), ("exclusiveMinimum", 1, 2),
                ("maximum", 2, 1), ("exclusiveMaximum", 1, 0)]:
            with self.subTest(bound=bound):
                schema = {"type": "number", bound: 1}
                self.assertTrue(checker.validate_value(invalid, schema, "test"))
                self.assertEqual(checker.validate_value(valid, schema, "test"), [])

    def test_boolean_is_not_a_resize_amount(self):
        self.assertTrue(checker.validate_value(True, {"type": "number"}, "amount"))

    def test_nested_required_and_unknown_arguments(self):
        schema = {"type": "object", "required": ["direction"], "properties": {
            "direction": {"type": "string", "enum": ["left", "right"]},
        }}
        problems = checker.validate_value({"direciton": "left"}, schema, "focus")
        self.assertEqual(len(problems), 2)
        self.assertEqual(checker.validate_value({"direction": "left"}, schema, "focus"), [])


class KeymapTests(unittest.TestCase):
    def test_history_and_submenus_cannot_be_one_shot(self):
        for mode, keys, target in (("", ["ctrl+b", "["], "history"),
                                   ("actions", ["["], "history"),
                                   ("actions", ["m"], "panes")):
            binding = {"mode": mode, "keys": keys, "action": "client.mode.enter",
                       "args": {"name": target, "once": True}}
            problems = checker.validate_keymap({"bindings": [binding]})
            self.assertTrue(any("persistently" in problem for problem in problems))
            binding["args"]["once"] = False
            problems = checker.validate_keymap({"bindings": [binding]})
            self.assertFalse(any("persistently" in problem for problem in problems))

    def test_duplicate_and_sequence_conflicts_are_reported(self):
        binding = {"keys": ["ctrl+b"], "action": "pane.zoom"}
        problems = checker.validate_keymap({"bindings": [binding, binding,
            {"keys": ["ctrl+b", "c"], "action": "client.tab.new"}]})
        self.assertTrue(any("duplicate binding" in problem for problem in problems))
        self.assertTrue(any("sequence conflict" in problem for problem in problems))

    def test_passthrough_override_does_not_conflict_with_global_prefix(self):
        problems = checker.validate_keymap({"bindings": [
            {"mode": "tmux-passthrough", "keys": ["ctrl+b"], "action": "pane.send_key"},
            {"keys": ["ctrl+b", "c"], "action": "client.tab.new"}]})
        self.assertFalse(any("sequence conflict" in problem for problem in problems))


if __name__ == "__main__":
    unittest.main()
