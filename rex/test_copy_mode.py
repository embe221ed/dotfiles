"""Exercise the Lua launcher and real Neovim keys/OSC 52 without a clipboard."""
import base64
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parent


class CopyModeTests(unittest.TestCase):
    def test_launcher(self):
        lua = shutil.which("lua")
        if not lua:
            self.skipTest("Lua is unavailable")
        result = subprocess.run([lua, str(ROOT / "test-copy-mode.lua")],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def editor(self, keys, expected, text="alpha one\nbravo two\ncharlie 界🚀\n\n\n",
               clipboard=False, copy_failure=False):
        nvim = shutil.which("nvim")
        if not nvim:
            self.skipTest("Neovim is unavailable")
        with tempfile.TemporaryDirectory(prefix="rex-copy-test-") as temp:
            directory = Path(temp)
            snapshot = directory / "snapshot with spaces"
            snapshot.write_text(text)
            marker = directory / "user-config-loaded"
            user_config = directory / "config/nvim"
            user_config.mkdir(parents=True)
            (user_config / "init.lua").write_text(
                "vim.fn.writefile({'unexpected'}, " + json.dumps(str(marker)) + ")")
            settings = {"path": str(snapshot)}
            copied_file = directory / "clipboard-result"
            if clipboard or copy_failure:
                provider = directory / "clipboard-command"
                body = ("sys.stderr.write('clipboard-test-failed'); sys.exit(1)" if copy_failure else
                        "pathlib.Path(" + repr(str(copied_file)) + ").write_bytes(sys.stdin.buffer.read())")
                provider.write_text("#!" + sys.executable + "\nimport pathlib, sys\n" + body + "\n")
                provider.chmod(0o700)
                settings["clipboard"] = str(provider)
            config = json.dumps(settings).replace("'", "''")
            command = [nvim, "--noplugin", "-i", "NONE", "-n", "-R",
                       "--cmd", "let g:rex_copy = json_decode('" + config + "')",
                       "-u", str(ROOT / "copy-editor.lua"), "--", str(snapshot)]
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
            env = dict(os.environ, HOME=temp, XDG_CONFIG_HOME=str(directory / "config"),
                       XDG_DATA_HOME=str(directory / "data"), XDG_STATE_HOME=str(directory / "state"),
                       XDG_CACHE_HOME=str(directory / "cache"), TERM="xterm-256color")
            env.pop("NVIM", None)
            output = bytearray()
            started = time.monotonic()
            process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                                       cwd=temp, env=env, start_new_session=True)
            os.close(slave)

            def read_until(predicate, timeout=5):
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    if select.select([master], [], [], .02)[0]:
                        try:
                            output.extend(os.read(master, 65536))
                        except OSError:
                            pass
                    if predicate():
                        return
                self.fail("Neovim did not reach the expected state: " + repr(bytes(output[-3000:])))

            try:
                read_until(lambda: b"Enter copy" in output and not snapshot.exists())
                ready_ms = (time.monotonic() - started) * 1000
                os.write(master, keys)
                if copy_failure:
                    read_until(lambda: b"clipboard-test-failed" in output)
                    self.assertIsNone(process.poll(), "failed copies must keep the viewer open")
                    os.write(master, b"q")
                read_until(lambda: process.poll() is not None)
                # Drain the final OSC and terminal-restoration output.
                while select.select([master], [], [], 0)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    output.extend(data)
                self.assertEqual(process.returncode, 0, repr(bytes(output[-2000:])))
                copied = re.findall(rb"\x1b\]52;c;([A-Za-z0-9+/=]*)\x1b\\", output)
                self.assertEqual([base64.b64decode(value).decode() for value in copied],
                                 [] if expected is None or clipboard else [expected])
                if clipboard:
                    self.assertEqual(copied_file.read_text(), expected)
                self.assertFalse(snapshot.exists())
                self.assertFalse(marker.exists(), "user Neovim config must not load")
                self.assertFalse(list(directory.rglob("*.shada*")))
                self.assertFalse(list(directory.rglob("*.swp")))
                return ready_ms
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=3)
                os.close(master)

    def test_character_selection(self):
        self.editor(b"gg0v4ly", "alpha")

    def test_line_selection_and_enter(self):
        self.editor(b"ggVj\r", "alpha one\nbravo two\n")

    def test_rectangle_selection(self):
        self.editor(b"gg0\x16j2ly", "alp\nbra")

    def test_search_and_yank_motion(self):
        self.editor(b"gg/bravo\rviwy", "bravo")

    def test_starts_at_last_nonblank_line_and_preserves_unicode(self):
        self.editor(b"\r", "charlie 界🚀\n")

    def test_cancel_does_not_copy(self):
        self.editor(b"q", None)

    def test_local_clipboard_receives_exact_unicode_text(self):
        self.editor(b"\r", "charlie 界🚀\n", clipboard=True)

    def test_failed_copy_keeps_the_viewer_open(self):
        self.editor(b"\r", None, copy_failure=True)

    def test_escape_clears_selection_then_closes(self):
        self.editor(b"v\x1b\x1b", None)

    def test_large_capture_keeps_last_line(self):
        self.editor(b"\r", "last line\n", text=("long history line " * 10 + "\n") * 12000 + "last line\n")


if __name__ == "__main__":
    unittest.main()
