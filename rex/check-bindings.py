#!/usr/bin/env python3
"""Check the loaded Rex keymap without changing the server or app.

Run `rex config reload` after edits, then run this script. Config check reads
the file on disk; keymap checks the server's loaded configuration. This script
compares the entry file's hash with the loaded keymap. Included Lua files and
shortcuts saved in the app's settings still require a reload and live check.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def find_rex(explicit):
    if explicit:
        return explicit
    found = shutil.which("rex")
    if found:
        return found
    for parent in (Path("/Applications"), Path.home() / "Applications"):
        for app in ("Rex Beta.app", "Rex.app"):
            binary = parent / app / "Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
            if binary.is_file():
                return str(binary)
    raise RuntimeError("Rex CLI not found; pass --rex /path/to/rex")


def run_json(binary, *arguments):
    command = [binary, "--autostart=false", "--color=never", *arguments]
    result = subprocess.run(command, capture_output=True, text=True, timeout=20)
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        detail = result.stderr.strip() or result.stdout.strip() or "no output"
        raise RuntimeError(f"{' '.join(arguments)}: {detail}") from None
    if result.returncode and not payload.get("diagnostics"):
        raise RuntimeError(result.stderr.strip() or f"command exited {result.returncode}")
    return payload


def select_client(binary, requested):
    if requested:
        return requested
    clients = run_json(binary, "client", "ls", "--json").get("clients") or []
    apps = [c for c in clients if (c.get("info") or {}).get("kind") == "app"
            and c.get("connection_state") == "connected"]
    if len(apps) != 1:
        labels = ", ".join(c.get("info", {}).get("label") or c["client_id"] for c in apps)
        raise RuntimeError("Use --client LABEL_OR_ID with one connected Rex app"
                           + (f"; found: {labels}" if labels else "; none connected"))
    return apps[0]["client_id"]


def binding_label(mode, keys):
    return (f"{mode}/" if mode else "") + ">".join(keys)


def validate_loaded_config(checked, keymap):
    """Don't report success for an old keymap after an edit or missing symlink."""
    loaded = keymap.get("config") or {}
    if not checked.get("exists"):
        return ["configuration file is missing: " + checked.get("path", "init.lua")]
    if loaded.get("path") != checked.get("path") or not loaded.get("exists"):
        return ["checked file is not the server's loaded configuration; reload Rex"]
    if not loaded.get("hash"):
        return ["server did not report a configuration hash; cannot verify the loaded file"]
    digest = hashlib.sha256(Path(checked["path"]).read_bytes()).hexdigest()
    if digest != loaded["hash"]:
        return ["init.lua changed since the server loaded it; reload Rex"]
    return []


def validate_value(value, schema, label):
    """Check the schema subset used by client shortcut arguments, not all JSON Schema."""
    problems = []
    is_number = isinstance(value, (int, float)) and not isinstance(value, bool)
    matches = {
        "null": value is None,
        "boolean": isinstance(value, bool),
        "integer": is_number and (isinstance(value, int) or value.is_integer()),
        "number": is_number,
        "string": isinstance(value, str),
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
    }
    types = schema.get("type", [])
    if isinstance(types, str):
        types = [types]
    if types and not any(matches.get(kind, False) for kind in types):
        return [f"{label}: expected {' or '.join(types)}"]
    if "enum" in schema and value not in schema["enum"]:
        problems.append(f"{label}: expected one of {schema['enum']}")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        for name in schema.get("required", []):
            if name not in value:
                problems.append(f"{label}: missing required argument {name}")
        for name, item in value.items():
            if name in properties:
                problems.extend(validate_value(item, properties[name], f"{label}.{name}"))
            else:
                # Flag undeclared argument names even when the schema omits
                # additionalProperties: an unknown shortcut option is likely a typo.
                problems.append(f"{label}: undeclared argument {name}")
    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for index, item in enumerate(value):
            problems.extend(validate_value(item, schema["items"], f"{label}[{index}]"))
    if is_number:
        for bound, operator in (("minimum", ">="), ("exclusiveMinimum", ">")):
            if bound in schema and (value < schema[bound] if bound == "minimum"
                                    else value <= schema[bound]):
                problems.append(f"{label}: must be {operator} {schema[bound]}")
        for bound, operator in (("maximum", "<="), ("exclusiveMaximum", "<")):
            if bound in schema and (value > schema[bound] if bound == "maximum"
                                    else value >= schema[bound]):
                problems.append(f"{label}: must be {operator} {schema[bound]}")
    return problems


def validate_client_arguments(bindings, actions):
    client_actions = {action["name"]: action for action in actions}
    problems = []
    for binding in bindings:
        action = client_actions.get(binding["action"])
        if action is None:
            continue
        label = binding_label(binding.get("mode", ""), binding["keys"])
        schema = action.get("args")
        arguments = binding.get("args", {})
        if schema is None:
            if arguments not in (None, {}):
                problems.append(f"{label}: {action['name']} declares no arguments")
        else:
            problems.extend(validate_value(arguments, schema, label))
    return problems


def validate_keymap(keymap):
    problems = []
    bindings = keymap.get("bindings") or []
    indexed = {}
    for binding in bindings:
        mode = binding.get("mode", "")
        keys = tuple(binding["keys"])
        identity = (mode, keys)
        if identity in indexed:
            problems.append(f"duplicate binding: {binding_label(mode, keys)}")
        else:
            indexed[identity] = binding
    # Only compare within the same mode. A passthrough mode intentionally
    # overrides the global Ctrl+B prefix while it is active.
    for (mode, keys) in indexed:
        for length in range(1, len(keys)):
            if (mode, keys[:length]) in indexed:
                problems.append("sequence conflict: " + binding_label(mode, keys[:length])
                                + " also starts " + binding_label(mode, keys))

    def require(mode, keys, action, args=None):
        binding = indexed.get((mode, tuple(keys.split(">"))))
        label = binding_label(mode, keys.split(">"))
        if not binding:
            problems.append(f"missing critical binding: {label}")
        else:
            actual_args = binding.get("args") or {}
            if not isinstance(actual_args, dict):
                actual_args = {}
            if binding["action"] != action or any(
                    actual_args.get(k) != v for k, v in (args or {}).items()):
                problems.append(f"unexpected critical binding: {label}")

    require("", "ctrl+b>n", "tmux_next_window")
    require("", "ctrl+b>p", "tmux_previous_window")
    for number in range(1, 10):
        require("", f"ctrl+b>{number}", f"tmux_window_{number}")
    require("", "alt+p", "tmux_scratch")
    require("", "ctrl+b>[", "client.mode.enter", {"name": "history"})
    require("", "ctrl+b>shift+8", "pane.new_floating")
    require("", "ctrl+b>r", "pane.rename")
    require("", "ctrl+b>=", "pane.balance")
    require("panes", "=", "pane.balance")
    require("", "ctrl+b>m", "pane.minimize_all_floating")
    require("", "shift+pageup", "client.scroll.page_up")
    require("", "shift+pagedown", "client.scroll.page_down")
    require("", "ctrl+b>enter", "client.mode.enter", {"name": "panes"})
    require("", "ctrl+b>a", "client.mode.enter", {"name": "actions"})
    # Native submenu entry handles a fast following movement key in the app.
    require("actions", "m", "client.mode.enter", {"name": "panes"})
    # Entries stay active until explicitly left. Making the menu one-shot
    # leaks fast following keys during its other actions' server callbacks.
    for identity, binding in indexed.items():
        arguments = binding.get("args") or {}
        if (binding["action"] == "client.mode.enter" and isinstance(arguments, dict)
                and arguments.get("name") in ("panes", "actions", "history")
                and arguments.get("once", False) is not False):
            problems.append(f"{binding_label(*identity)} must enter {arguments['name']} persistently")
    for (mode, keys) in indexed:
        if not mode and len(keys) > 2 and keys[:2] == ("ctrl+b", "a"):
            problems.append("legacy action-menu sequence: " + binding_label(mode, keys))
    # Pane mode can sit over actions; exit the complete stack on cancellation.
    for mode in ("panes", "history"):
        for key in ("q", "esc", "enter", "ctrl+c", "f12"):
            require(mode, key, "client.mode.exit_all")
    # Cancellation uses the same ordered callback path as selection; a native
    # exit can run before a pending selection and have its mode reopen later.
    require("actions", "q", "tmux_menu_cancel")
    require("actions", "esc", "tmux_menu_cancel")
    require("actions", "[", "client.mode.enter", {"name": "history"})
    require("history", "/", "tmux_history_find")
    require("history", "y", "tmux_history_copy")
    for key, action in (("k", "client.scroll.page_up"), ("j", "client.scroll.page_down"),
                        ("shift+k", "client.prompt.previous"), ("shift+j", "client.prompt.next")):
        require("history", key, action)
    for key, action in (("shift+\\", "tmux_menu_split_right"), ("-", "tmux_menu_split_down"),
                        ("shift+8", "tmux_menu_floating"), ("c", "tmux_menu_new_window"),
                        (",", "tmux_menu_rename_window"), ("shift+1", "tmux_menu_break_pane"),
                        ("z", "tmux_menu_zoom"), ("d", "tmux_menu_toggle_float"),
                        ("r", "tmux_menu_rename_pane"), ("=", "tmux_menu_balance"),
                        ("p", "tmux_menu_scratch")):
        require("actions", key, action)
    require("actions", "w", "tmux_menu_navigator")
    # A partially loaded optional integration may still declare some actions.
    # The actual binding chooses whether navigation uses Interdimux or native UI.
    switcher = indexed.get(("", ("ctrl+b", "f")), {}).get("action")
    if switcher == "interdimux":
        require("", "ctrl+b>f", "interdimux")
        require("", "ctrl+b>w", "interdimux")
        require("", "ctrl+b>e", "interdimux_agents")
        require("", "ctrl+b>tab", "interdimux_agent_next")
    else:
        require("", "ctrl+b>f", "pane.go_to")
        require("", "ctrl+b>w", "pane.go_to")
        require("", "ctrl+b>g", "client.palette.toggle")
        require("", "ctrl+b>e", "client.sidebar.activity.toggle")
        require("", "ctrl+b>tab", "client.sidebar.activity.toggle")
    for key, direction in (("h", "left"), ("j", "down"), ("k", "up"), ("l", "right")):
        require("panes", key, "pane.focus." + direction)
        require("panes", "shift+" + key, "pane.resize", {"direction": direction, "amount": 2})
        for mode, prefix in (("panes", ""), ("", "ctrl+b>")):
            require(mode, prefix + "ctrl+" + key, "pane.resize", {"direction": direction, "amount": 2})
            require(mode, prefix + "alt+" + key, "pane.move." + direction)
    require("", "f12", "client.mode.enter", {"name": "tmux-passthrough"})
    require("tmux-passthrough", "f12", "client.mode.exit")
    require("tmux-passthrough", "ctrl+b", "pane.send_key", {"key": "ctrl+b"})
    require("tmux-passthrough", "esc", "pane.send_key", {"key": "escape"})
    modes = {mode["name"]: mode for mode in keymap.get("modes") or []}
    for name, exclusive in (("actions", True), ("panes", True), ("history", True), ("tmux-passthrough", False)):
        if name not in modes or modes[name].get("exclusive") is not exclusive:
            problems.append(f"mode {name} must have exclusive={str(exclusive).lower()}")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client", help="connected Rex app label or ID")
    parser.add_argument("--rex", help="path to the Rex CLI")
    options = parser.parse_args()
    binary = find_rex(options.rex)
    checked = run_json(binary, "config", "check", "--json")
    client = select_client(binary, options.client)
    actions = run_json(binary, "-C", client, "actions", "--json").get("actions", [])
    client_actions = [action for action in actions if action.get("kind") == "client"]
    if not client_actions:
        raise RuntimeError("The selected client reports no client actions")
    # The server checks action names and server-action arguments. It delegates
    # client argument checks to the app, so check the used schema subset below.
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as request:
        json.dump({"actions": client_actions, "server_actions": "configured"}, request)
        request.flush()
        keymap = run_json(binary, "keymap", "--request", request.name, "--json")
    problems = validate_loaded_config(checked, keymap)
    for report in (checked, keymap):
        for diagnostic in report.get("diagnostics") or []:
            problems.append(f"{diagnostic.get('severity', 'warning')}: "
                            f"{diagnostic.get('source', '')} {diagnostic['message']}".strip())
    problems.extend(validate_keymap(keymap))
    problems.extend(validate_client_arguments(keymap.get("bindings") or [], client_actions))
    if problems:
        for problem in dict.fromkeys(problems):
            print(f"FAIL: {problem}", file=sys.stderr)
        print("Reload with `rex config reload` after edits, then rerun.", file=sys.stderr)
        return 1
    print(f"PASS: {len(keymap.get('bindings', []))} loaded bindings; "
          f"{len(keymap.get('modes', []))} modes; client action names and supported argument checks passed.")
    print("Entry-file hash matches the server. Reload after included Lua edits; app-saved shortcuts are not checked.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
