#!/usr/bin/env python3
"""
Claude Code agent-state writer (Islet).

Invoked by Claude Code hooks. Reads the hook payload on stdin and records a small status file at
``~/.claude/agent-tui-state/<session_id>.json`` so Islet can show whether this session is working,
waiting, or done. It only writes a status file and never blocks the agent (always exits 0).

Status is derived by Islet from the recorded ``hook_event_name`` (e.g. ``Stop`` -> done,
``Notification`` -> waiting, anything else -> working) plus the file's modification time.
"""

import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

# Allowlist applied to the session id before it is used in a filename. External input must never be
# used verbatim in a file path (Secure Python rule #1 / #2), so any character outside this set is
# replaced and a safe fallback is used if nothing usable remains.
_UNSAFE = re.compile(r"[^A-Za-z0-9._-]")
# Focus hints (terminal session id / tty / program) are later interpolated into AppleScript by the
# app, so they're held to a strict allowlist here too. Empty string means "unknown".
_FOCUS_UNSAFE = re.compile(r"[^A-Za-z0-9._:/-]")
# Cap any displayed activity text so we never persist large / sensitive blobs (Secure rule #5).
_ACTIVITY_MAX = 60


def _sanitize(value: str, fallback: str = "unknown") -> str:
    cleaned = _UNSAFE.sub("_", value).strip("._")
    return cleaned or fallback


def _sanitize_focus(value: str) -> str:
    return _FOCUS_UNSAFE.sub("", value)[:128]


def _clip(text: str) -> str:
    text = " ".join(text.split())
    return text[:_ACTIVITY_MAX]


def _activity(event: str, payload: dict) -> str:
    """A short, privacy-safe phrase describing the current step.

    We deliberately avoid persisting full prompts or command arguments (Secure rule #5): only a
    tool name plus a coarse target (a file basename, a command's program token, or a generic verb).
    """
    if event == "UserPromptSubmit":
        return "Thinking\u2026"
    if event == "Notification":
        # Notification messages vary per event (permission asks, plain questions, idle nudges), so
        # a generic phrase reads consistently instead of leaking the specific, ever-changing prompt.
        return "Needs your input"
    if event in ("Stop", "SubagentStop"):
        return ""
    if event in ("PreToolUse", "PostToolUse"):
        tool = str(payload.get("tool_name", "")).strip()
        tin = payload.get("tool_input")
        tin = tin if isinstance(tin, dict) else {}
        path = tin.get("file_path") or tin.get("notebook_path")
        base = os.path.basename(str(path)) if isinstance(path, str) and path else ""
        if tool in ("Edit", "MultiEdit", "Write", "NotebookEdit"):
            return _clip(f"Editing {base}" if base else "Editing")
        if tool == "Read":
            return _clip(f"Reading {base}" if base else "Reading")
        if tool == "Bash":
            cmd = str(tin.get("command", "")).strip()
            token = cmd.split()[0] if cmd else ""
            token = os.path.basename(token)
            return _clip(f"Running {token}" if token else "Running command")
        if tool in ("Grep", "Glob"):
            return "Searching"
        if tool in ("WebFetch", "WebSearch"):
            return "Browsing the web"
        if tool == "Task":
            return "Running a subagent"
        return _clip(tool) if tool else "Working\u2026"
    return "Working\u2026"


def _tty() -> str:
    """Best-effort controlling tty so the app can refocus the exact terminal tab. stdin is the
    hook payload pipe, so probe stdout/stderr instead. Failures are non-fatal."""
    for fd in (1, 2, 0):
        try:
            return _sanitize_focus(os.ttyname(fd))
        except OSError:
            continue
    return ""


def main() -> None:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, OSError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    session_id = _sanitize(str(payload.get("session_id", "unknown")))
    event = str(payload.get("hook_event_name", ""))
    env = os.environ
    record = {
        "session_id": session_id,
        "hook_event_name": event,
        "cwd": str(payload.get("cwd", "")),
        "activity": _activity(event, payload),
        "term_program": _sanitize_focus(env.get("TERM_PROGRAM", "")),
        # __CFBundleIdentifier is set by macOS to the hosting app's bundle id (e.g. com.apple.Terminal,
        # com.googlecode.iterm2, the Cursor/VS Code id) — the most reliable way to refocus that app.
        "app_bundle": _sanitize_focus(env.get("__CFBundleIdentifier", "")),
        "term_session": _sanitize_focus(
            env.get("ITERM_SESSION_ID", "") or env.get("TERM_SESSION_ID", "")
        ),
        "tty": _tty(),
        "ts": time.time(),
    }

    state_dir = Path.home() / ".claude" / "agent-tui-state"
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        # Atomic write (temp file + os.replace) so Islet never reads a half-written file.
        tmp_fd, tmp_path = tempfile.mkstemp(dir=str(state_dir), suffix=".tmp")
        with os.fdopen(tmp_fd, "w") as handle:
            json.dump(record, handle)
        os.replace(tmp_path, state_dir / f"{session_id}.json")
    except OSError:
        # Best-effort only: never fail the hook over a status-file write.
        try:
            os.unlink(tmp_path)  # type: ignore[name-defined]
        except (OSError, NameError):
            pass


if __name__ == "__main__":
    main()
    sys.exit(0)
