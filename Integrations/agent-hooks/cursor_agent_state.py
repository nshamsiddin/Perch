#!/usr/bin/env python3
"""
Cursor agent-state writer (Islet).

Invoked by Cursor hooks. The first argv selects the mode:
  ``working`` (beforeSubmitPrompt) / ``done`` (stop) / ``edit`` (afterFileEdit) /
  ``shell`` (beforeShellExecution).
Reads the hook payload on stdin for the conversation id + workspace, then records
``~/.cursor/agent-status/<conversation_id>.json`` so Islet can show Cursor's agent activity plus a
short "what it's doing" line.

Fails open: any error still exits 0 and emits an empty JSON object so it never blocks Cursor.
"""

import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

# Allowlist applied to the conversation id before it is used in a filename. External input must
# never be used verbatim in a file path (Secure Python rule #1 / #2).
_UNSAFE = re.compile(r"[^A-Za-z0-9._-]")
# edit/shell are working sub-modes that also carry an activity phrase.
_ALLOWED_MODES = {"working", "done", "edit", "shell"}
_ACTIVITY_MAX = 60


def _sanitize(value: str, fallback: str = "unknown") -> str:
    cleaned = _UNSAFE.sub("_", value).strip("._")
    return cleaned or fallback


def _clip(text: str) -> str:
    return " ".join(text.split())[:_ACTIVITY_MAX]


def _activity(mode: str, payload: dict) -> str:
    """A short, privacy-safe phrase. Only a coarse target is kept (a file basename or a command's
    program token) — never full file contents or command arguments (Secure rule #5)."""
    if mode == "edit":
        path = payload.get("file_path") or payload.get("path")
        base = os.path.basename(str(path)) if isinstance(path, str) and path else ""
        return _clip(f"Editing {base}" if base else "Editing")
    if mode == "shell":
        cmd = payload.get("command")
        if not isinstance(cmd, str):
            cmd = ""
        token = os.path.basename(cmd.split()[0]) if cmd.split() else ""
        return _clip(f"Running {token}" if token else "Running command")
    if mode == "working":
        return "Thinking\u2026"
    return ""


def main() -> None:
    # The mode comes from our own hook config via argv, not user input, but it is still validated
    # against an allowlist before use.
    mode = sys.argv[1] if len(sys.argv) > 1 else "working"
    if mode not in _ALLOWED_MODES:
        mode = "working"
    status = "done" if mode == "done" else "working"

    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, OSError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    conversation_id = _sanitize(str(payload.get("conversation_id", "unknown")))
    roots = payload.get("workspace_roots")
    cwd = roots[0] if isinstance(roots, list) and roots and isinstance(roots[0], str) else ""

    record = {
        "tool": "cursor",
        "status": status,
        "conversation_id": conversation_id,
        "cwd": cwd,
        "activity": _activity(mode, payload),
        "ts": time.time(),
    }

    state_dir = Path.home() / ".cursor" / "agent-status"
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        tmp_fd, tmp_path = tempfile.mkstemp(dir=str(state_dir), suffix=".tmp")
        with os.fdopen(tmp_fd, "w") as handle:
            json.dump(record, handle)
        os.replace(tmp_path, state_dir / f"{conversation_id}.json")
    except OSError:
        try:
            os.unlink(tmp_path)  # type: ignore[name-defined]
        except (OSError, NameError):
            pass

    # Cursor command hooks may parse stdout as JSON; an empty object is a no-op (allow/continue).
    sys.stdout.write("{}")


if __name__ == "__main__":
    main()
    sys.exit(0)
