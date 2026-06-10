#!/usr/bin/env python3
"""
Idempotently merge Perch's agent-status writers into the Claude Code and Cursor hook configs.

Only *adds* Perch entries when they are absent; it never removes or rewrites the user's existing
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

# Claude Code Control: the PreToolUse gate that lets Perch approve/deny tool calls. Scoped by a
# matcher to the side-effecting tools so trivial reads/searches never invoke it. The gate only
# blocks when the user has enabled Control in Perch; otherwise it just records monitoring state.
CLAUDE_GATE_CMD = "python3 ~/.claude/hooks/claude_agent_gate.py"
CLAUDE_GATE_MARKER = "claude_agent_gate.py"
CLAUDE_GATE_EVENT = "PreToolUse"
CLAUDE_GATE_MATCHER = "Bash|Write|Edit|MultiEdit|NotebookEdit|WebFetch"

# Cursor: lifecycle + activity writers (schema v1). Paths are relative to ~/.cursor (user hooks run
# there). edit refreshes the "working" state and carries a short activity phrase. Shell/MCP execution
# go through the gate so Perch's Control can approve/deny/stop them (the gate also records state).
CURSOR_CMDS = {
    "beforeSubmitPrompt": "python3 ./hooks/cursor_agent_state.py working",
    "afterFileEdit": "python3 ./hooks/cursor_agent_state.py edit",
    "beforeShellExecution": "python3 ./hooks/cursor_agent_gate.py shell",
    "beforeMCPExecution": "python3 ./hooks/cursor_agent_gate.py mcp",
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

    # Register the PreToolUse gate (matcher-scoped) for Perch's Control feature.
    gate_groups = hooks.setdefault(CLAUDE_GATE_EVENT, [])
    if isinstance(gate_groups, list):
        gate_present = any(
            CLAUDE_GATE_MARKER in entry.get("command", "")
            for group in gate_groups
            if isinstance(group, dict)
            for entry in group.get("hooks", [])
            if isinstance(entry, dict)
        )
        if not gate_present:
            gate_groups.append({
                "matcher": CLAUDE_GATE_MATCHER,
                "hooks": [{"type": "command", "command": CLAUDE_GATE_CMD}],
            })
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
