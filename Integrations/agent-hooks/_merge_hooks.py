#!/usr/bin/env python3
"""
Idempotently merge Islet's agent-status writers into the Claude Code and Cursor hook configs.

Only *adds* Islet entries when they are absent; it never removes or rewrites the user's existing
hooks. A ``.bak`` backup is written before modifying an existing config file. Run via ``install.sh``.
"""

import json
import shutil
from pathlib import Path

# Claude Code: a matcher-less command hook on each lifecycle event that doesn't already record
# state. (PreToolUse/PostToolUse/Stop are typically already wired by the user.)
CLAUDE_CMD = "python3 ~/.claude/hooks/claude_agent_state.py"
CLAUDE_EVENTS = ["UserPromptSubmit", "Notification", "SubagentStop"]
CLAUDE_MARKER = "claude_agent_state.py"

# Cursor: lifecycle + activity writers (schema v1). Paths are relative to ~/.cursor (user hooks run
# there). edit/shell refresh the "working" state and carry a short activity phrase.
CURSOR_CMDS = {
    "beforeSubmitPrompt": "python3 ./hooks/cursor_agent_state.py working",
    "afterFileEdit": "python3 ./hooks/cursor_agent_state.py edit",
    "beforeShellExecution": "python3 ./hooks/cursor_agent_state.py shell",
    "stop": "python3 ./hooks/cursor_agent_state.py done",
}


def _load(path: Path):
    if not path.exists():
        return {}
    try:
        with path.open() as handle:
            return json.load(handle)
    except (ValueError, OSError):
        return {}


def _backup_and_write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
    with path.open("w") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def merge_claude() -> bool:
    path = Path.home() / ".claude" / "settings.json"
    data = _load(path)
    if not isinstance(data, dict):
        data = {}
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        return False

    changed = False
    for event in CLAUDE_EVENTS:
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            continue
        already = any(
            CLAUDE_MARKER in entry.get("command", "")
            for group in groups
            if isinstance(group, dict)
            for entry in group.get("hooks", [])
            if isinstance(entry, dict)
        )
        if not already:
            groups.append({"hooks": [{"type": "command", "command": CLAUDE_CMD}]})
            changed = True

    if changed:
        _backup_and_write(path, data)
    return changed


def merge_cursor() -> bool:
    path = Path.home() / ".cursor" / "hooks.json"
    data = _load(path)
    if not isinstance(data, dict) or not data:
        data = {"version": 1, "hooks": {}}
    data.setdefault("version", 1)
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        return False

    changed = False
    for event, command in CURSOR_CMDS.items():
        entries = hooks.setdefault(event, [])
        if not isinstance(entries, list):
            continue
        already = any(
            isinstance(entry, dict) and entry.get("command") == command for entry in entries
        )
        if not already:
            entries.append({"command": command})
            changed = True

    if changed:
        _backup_and_write(path, data)
    return changed


def main() -> None:
    claude_changed = merge_claude()
    cursor_changed = merge_cursor()
    print(f"  Claude settings.json: {'updated' if claude_changed else 'already configured'}")
    print(f"  Cursor hooks.json:    {'updated' if cursor_changed else 'already configured'}")


if __name__ == "__main__":
    main()
