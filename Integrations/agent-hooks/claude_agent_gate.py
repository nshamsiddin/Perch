#!/usr/bin/env python3
"""
Claude Code PreToolUse gate (Perch).

Runs on ``PreToolUse``. It always records the same monitoring state as ``claude_agent_state.py`` so
the session keeps showing in the island. In addition, when the user has turned on *Control* in Perch
(a gating flag Perch writes) and the tool is in the gated set, this hook BLOCKS: it marks the session
as awaiting approval, then polls Perch's per-session command file for an allow/deny decision and
returns the matching ``PreToolUse`` ``permissionDecision``.

Safety:
  * Default is non-blocking. With Control off (or a non-gated tool) it just writes state and exits 0.
  * On timeout it exits 0 with NO JSON, which defers to Claude's native permission prompt. It never
    defaults to ``allow`` (returning ``allow`` would silently bypass Claude's permission system).
  * The poll timeout is kept just under Claude's default 60s hook timeout so we always return our own
    "defer" rather than being killed (a kill is treated by Claude as proceed).
  * Decisions are matched by ``request_id`` so a stale decision from a previous prompt is ignored; a
    recent ``stop`` request denies the next gated call as a backstop for Stop.
"""

import json
import os
import sys
import time
import uuid
from pathlib import Path

# Import the shared monitoring helpers. Both scripts are installed side-by-side in ~/.claude/hooks,
# so this is an ordinary static import of a local module (no dynamic/user-controlled import).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import claude_agent_state as cas  # noqa: E402

# Tools routed through the island by default. The PreToolUse matcher in settings.json already scopes
# which tools invoke this script; this is the in-hook backstop (and lets Perch narrow the set later).
_DEFAULT_GATED_TOOLS = {"Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "WebFetch"}
_ALLOWED_DECISIONS = {"allow", "deny"}
# Kept under Claude's default 60s hook timeout so we emit our own defer before Claude gives up.
_POLL_TIMEOUT_SECONDS = 55.0
_POLL_INTERVAL_SECONDS = 0.25
# A stop request only denies tool calls it precedes by at most this long, so an old stop file can't
# wedge a session forever.
_STOP_TTL_SECONDS = 120.0
_TEXT_MAX = 280

_COMMANDS_DIR = Path.home() / ".claude" / "agent-commands"


def _parse_paused_until(data: dict) -> float | None:
    """Returns a Unix timestamp when gating is paused, or None."""
    raw = data.get("gating_paused_until")
    if raw is None or raw is False:
        return None
    if not isinstance(raw, str) or not raw.strip():
        return None
    try:
        # ISO-8601 from Perch (e.g. 2026-06-10T12:00:00Z).
        from datetime import datetime, timezone

        text = raw.strip().replace("Z", "+00:00")
        dt = datetime.fromisoformat(text)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except (ValueError, TypeError):
        return None


def _gating_paused(data: dict) -> bool:
    """True when Perch has snoozed gating and the pause window has not elapsed."""
    until = _parse_paused_until(data)
    return until is not None and time.time() < until


def _load_config() -> tuple[bool, set, bool]:
    """Reads Perch's gating config. Returns (gating_enabled, gated_tool_set, paused)."""
    path = _COMMANDS_DIR / "_config.json"
    try:
        with path.open() as handle:
            data = json.load(handle)
    except (ValueError, OSError):
        return False, _DEFAULT_GATED_TOOLS, False
    if not isinstance(data, dict):
        return False, _DEFAULT_GATED_TOOLS, False
    gating = data.get("gating") is True
    paused = _gating_paused(data)
    tools = data.get("tools")
    if isinstance(tools, list):
        gated = {str(t) for t in tools if isinstance(t, str)}
    else:
        gated = _DEFAULT_GATED_TOOLS
    return gating, (gated or _DEFAULT_GATED_TOOLS), paused


def _read_command(session_id: str):
    """Reads the per-session command file Perch writes, or None. `session_id` is already sanitized
    by build_record, so it is safe to use as a path component (Secure Python rule #1)."""
    path = _COMMANDS_DIR / f"{session_id}.json"
    try:
        with path.open() as handle:
            data = json.load(handle)
    except (ValueError, OSError):
        return None
    return data if isinstance(data, dict) else None


def _consume_command(session_id: str) -> None:
    """Removes a command file once acted on, so a decision is applied exactly once."""
    try:
        (_COMMANDS_DIR / f"{session_id}.json").unlink()
    except OSError:
        pass


def _clip(value, fallback: str = "") -> str:
    text = value if isinstance(value, str) else ""
    text = " ".join(text.split())[:_TEXT_MAX]
    return text or fallback


def _resolve(cmd: dict, request_id: str):
    """Maps a command file to a decision tuple (decision, reason, note), or None if not applicable.

    All external values are validated before use: `decision` against an allowlist, `ts` as a number,
    text fields clipped. Nothing here is used in a file path, shell, or eval (Secure Python rules)."""
    ts = cmd.get("ts")
    recent = isinstance(ts, (int, float)) and (time.time() - ts) <= _STOP_TTL_SECONDS
    if cmd.get("stop") is True and recent:
        return ("deny", _clip(cmd.get("reason"), "Stopped from Perch"), None)
    if cmd.get("request_id") == request_id:
        decision = cmd.get("decision")
        if decision in _ALLOWED_DECISIONS:
            reason = _clip(cmd.get("reason")) or None
            note = _clip(cmd.get("note")) or None
            return (decision, reason, note)
    return None


def _target(payload: dict) -> str:
    """A coarse target for the approval summary (file basename / command token) — never full args."""
    tin = payload.get("tool_input")
    tin = tin if isinstance(tin, dict) else {}
    path = tin.get("file_path") or tin.get("notebook_path")
    if isinstance(path, str) and path:
        return _clip(os.path.basename(path))
    cmd = tin.get("command")
    if isinstance(cmd, str) and cmd.split():
        return _clip(os.path.basename(cmd.split()[0]))
    return ""


def _emit_allow(note) -> None:
    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}
    if note:
        out["hookSpecificOutput"]["additionalContext"] = note
    sys.stdout.write(json.dumps(out))


def _emit_deny(reason: str) -> None:
    sys.stdout.write(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason or "Denied from Perch",
        }
    }))


def main() -> None:
    payload = cas.read_payload()
    session_id, record = cas.build_record(payload)
    # The hook's parent is the Claude process; record it best-effort so Perch's Stop can SIGINT it.
    record["pid"] = os.getppid()
    tool_name = str(payload.get("tool_name", "")).strip()

    gating, gated_tools, paused = _load_config()
    if not gating or paused or tool_name not in gated_tools:
        # Control off or non-gated tool: behave exactly like the plain writer (no blocking, defer).
        cas.write_record(session_id, record)
        return

    request_id = uuid.uuid4().hex
    summary = record.get("activity") or tool_name or "tool call"
    record.update({
        "pending": True,
        "request_id": request_id,
        "tool_name": tool_name,
        "target": _target(payload),
        "activity": summary,
    })
    cas.write_record(session_id, record)

    decision = reason = note = None
    deadline = time.time() + _POLL_TIMEOUT_SECONDS
    while time.time() < deadline:
        cmd = _read_command(session_id)
        if cmd is not None:
            resolved = _resolve(cmd, request_id)
            if resolved is not None:
                decision, reason, note = resolved
                _consume_command(session_id)
                break
        time.sleep(_POLL_INTERVAL_SECONDS)

    # No longer blocking on the island: clear the pending markers regardless of outcome.
    for key in ("pending", "request_id", "tool_name", "target"):
        record.pop(key, None)
    cas.write_record(session_id, record)

    if decision == "allow":
        _emit_allow(note)
    elif decision == "deny":
        _emit_deny(reason or "Denied from Perch")
    # else: timed out -> exit 0 with no JSON -> defer to Claude's native permission prompt.


if __name__ == "__main__":
    main()
    sys.exit(0)
