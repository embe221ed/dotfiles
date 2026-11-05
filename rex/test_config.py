"""Run the Lua behavior suite with the actual init.lua, without a Rex server."""

import shutil
import subprocess
import unittest
from pathlib import Path


class ConfigBehaviorTests(unittest.TestCase):
    def test_lua_behaviors(self):
        lua = shutil.which("lua")
        if not lua:
            self.skipTest("Install Lua 5.2+ to run configuration behavior tests")
        root = Path(__file__).resolve().parent
        result = subprocess.run(
            [lua, str(root / "test-config.lua"), str(root / "init.lua")],
            text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("14 Lua behavioral scenarios", result.stdout)


if __name__ == "__main__":
    unittest.main()
