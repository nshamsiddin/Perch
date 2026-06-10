#!/usr/bin/env python3
"""
Idempotently remove Perch's agent-status writers from the Claude Code and Cursor hook configs.

The inverse of ``_merge_hooks.py``: it strips only the hook entries Perch added (identified by the
script names in their commands) and leaves every other hook untouched. Empty hook groups / events
left behind by the removal are pruned. A ``.bak`` backup is written before modifying a config.
Run via ``uninstall.sh``.
"""

import json
import shutil
from pathlib import Path

# Any Claude/Cursor hook entry whose command references one of these scripts is ours to remove.
PERCH_MARKERS = (
    "claude_agent_state.py",
    "claude_agent_gate.py",
    "cursor_agent_state.py",
    "cursor_agent_gate.py",
)

# Cursor events Perch wires (only these are scanned; other events are never touched).
CURSOR_EVENTS = (
    "beforeSubmitPrompt",
    "afterFileEdit",
    "beforeShellExecution",
    "beforeMCPExecution",
    "stop",
)


def _load(path: Path):
    if not path.exists():
        return None
    try:
        with path.open() as handle:
            return json.load(handle)
    except (ValueError, OSError):
        return None


def _backup_and_write(path: Path, data) -> None:
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
    with path.open("w") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def _is_perch_command(command) -> bool:
    return isinstance(command, str) and any(marker in command for marker in PERCH_MARKERS)


def unmerge_claude() -> bool:
    path = Path.home() / ".claude" / "settings.json"
    data = _load(path)
    if not isinstance(data, dict):
        return False
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return False

    changed = False
    # Claude shape: hooks[event] -> [ {"matcher"?, "hooks": [ {"type","command"}, ... ]}, ... ]
    for event in list(hooks.keys()):
        groups = hooks.get(event)
        if not isinstance(groups, list):
            continue
        kept_groups = []
        for group in groups:
            if not isinstance(group, dict):
                kept_groups.append(group)
                continue
            entries = group.get("hooks")
            if isinstance(entries, list):
                kept_entries = [
                    entry for entry in entries
                    if not (isinstance(entry, dict) and _is_perch_command(entry.get("command")))
                ]
                if len(kept_entries) != len(entries):
                    changed = True
                group["hooks"] = kept_entries
                # Drop a group we emptied out (don't drop groups that were already empty).
                if not kept_entries:
                    continue
            kept_groups.append(group)
        if len(kept_groups) != len(groups):
            changed = True
        if kept_groups:
            hooks[event] = kept_groups
        else:
            del hooks[event]

    if changed:
        _backup_and_write(path, data)
    return changed


def unmerge_cursor() -> bool:
    path = Path.home() / ".cursor" / "hooks.json"
    data = _load(path)
    if not isinstance(data, dict):
        return False
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return False

    changed = False
    # Cursor shape: hooks[event] -> [ {"command": "..."}, ... ]
    for event in CURSOR_EVENTS:
        entries = hooks.get(event)
        if not isinstance(entries, list):
            continue
        kept = [
            entry for entry in entries
            if not (isinstance(entry, dict) and _is_perch_command(entry.get("command")))
        ]
        if len(kept) != len(entries):
            changed = True
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]

    if changed:
        _backup_and_write(path, data)
    return changed


def main() -> None:
    claude_changed = unmerge_claude()
    cursor_changed = unmerge_cursor()
    print(f"  Claude settings.json: {'cleaned' if claude_changed else 'no Perch entries found'}")
    print(f"  Cursor hooks.json:    {'cleaned' if cursor_changed else 'no Perch entries found'}")


if __name__ == "__main__":
    main()
