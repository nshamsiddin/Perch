#!/usr/bin/env python3
"""
Cursor execution gate (Perch).

Wired to ``beforeShellExecution`` / ``beforeMCPExecution``. It records the same monitoring state as
``cursor_agent_state.py`` and, when the user has turned on *Control* in Perch, BLOCKS the execution
until the island decides: it polls Perch's per-conversation command file and then either allows the
call (exit 0) or denies it (exit 2 + a deny payload).

Why exit codes: Cursor currently honors only ``deny`` / exit code 2 for blocking (``ask``/``allow``
are ignored in several paths), so we never rely on ``ask``. Holding this process open is what makes
Cursor wait — so the gate effectively gives interactive approve/deny by returning a concrete
allow/deny once the island answers.

Safety: default is non-blocking (Control off -> allow). The poll timeout is kept short, under
Cursor's hook timeout, and on timeout the gate FAILS OPEN (allows) so a closed Perch never wedges an
agent. A recent ``stop`` request denies as a backstop for Perch's Stop. Experimental: behavior
depends on Cursor's evolving hook semantics and timeout.
"""

import json
import os
import sys
import time
import uuid
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cursor_agent_state as cas  # noqa: E402

_ALLOWED_DECISIONS = {"allow", "deny"}
# Conservatively under Cursor's hook timeout so we return our own allow before Cursor gives up.
_POLL_TIMEOUT_SECONDS = 25.0
_POLL_INTERVAL_SECONDS = 0.2
_STOP_TTL_SECONDS = 120.0
_TEXT_MAX = 280

_COMMANDS_DIR = Path.home() / ".cursor" / "agent-commands"


def _parse_paused_until(data: dict):
    raw = data.get("gating_paused_until")
    if raw is None or raw is False:
        return None
    if not isinstance(raw, str) or not raw.strip():
        return None
    try:
        from datetime import datetime, timezone

        text = raw.strip().replace("Z", "+00:00")
        dt = datetime.fromisoformat(text)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except (ValueError, TypeError):
        return None


def _gating_paused(data: dict) -> bool:
    until = _parse_paused_until(data)
    return until is not None and time.time() < until


def _load_config() -> tuple[bool, bool]:
    path = _COMMANDS_DIR / "_config.json"
    try:
        with path.open() as handle:
            data = json.load(handle)
    except (ValueError, OSError):
        return False, False
    if not isinstance(data, dict):
        return False, False
    return data.get("gating") is True, _gating_paused(data)


def _gating_enabled() -> bool:
    enabled, paused = _load_config()
    return enabled and not paused


def _read_command(conversation_id: str):
    # conversation_id is already sanitized by build_record, so it is safe as a path component.
    path = _COMMANDS_DIR / f"{conversation_id}.json"
    try:
        with path.open() as handle:
            data = json.load(handle)
    except (ValueError, OSError):
        return None
    return data if isinstance(data, dict) else None


def _consume_command(conversation_id: str) -> None:
    try:
        (_COMMANDS_DIR / f"{conversation_id}.json").unlink()
    except OSError:
        pass


def _clip(value, fallback: str = "") -> str:
    text = value if isinstance(value, str) else ""
    return " ".join(text.split())[:_TEXT_MAX] or fallback


def _resolve(cmd: dict, request_id: str):
    """Returns (decision, reason) or None. All external values are validated before use; nothing is
    used in a path, shell, or eval (Secure Python rules)."""
    ts = cmd.get("ts")
    recent = isinstance(ts, (int, float)) and (time.time() - ts) <= _STOP_TTL_SECONDS
    if cmd.get("stop") is True and recent:
        return ("deny", _clip(cmd.get("reason"), "Stopped from Perch"))
    if cmd.get("request_id") == request_id:
        decision = cmd.get("decision")
        if decision in _ALLOWED_DECISIONS:
            return (decision, _clip(cmd.get("reason")) or "Denied from Perch")
    return None


def _target(payload: dict) -> str:
    cmd = payload.get("command")
    if isinstance(cmd, str) and cmd.split():
        return _clip(os.path.basename(cmd.split()[0]))
    name = payload.get("tool_name") or payload.get("name")
    return _clip(name if isinstance(name, str) else "")


def _allow() -> None:
    # Empty object is a no-op (allow/continue) for Cursor command hooks.
    sys.stdout.write("{}")
    sys.exit(0)


def _deny(reason: str) -> None:
    sys.stdout.write(json.dumps({
        "permission": "deny",
        "user_message": "Denied from Perch",
        "agent_message": reason or "Denied from Perch",
    }))
    # Exit 2 is the reliable block signal for Cursor hooks.
    sys.exit(2)


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "shell"
    payload = cas.read_payload()
    conversation_id, record = cas.build_record("shell" if mode == "shell" else "working", payload)

    if not _gating_enabled():
        cas.write_record(conversation_id, record)
        _allow()
        return

    request_id = uuid.uuid4().hex
    target = _target(payload)
    record.update({
        "pending": True,
        "request_id": request_id,
        "tool_name": mode,
        "target": target,
        "activity": ("Approve: " + target) if target else "Needs your approval",
    })
    cas.write_record(conversation_id, record)

    decision = reason = None
    deadline = time.time() + _POLL_TIMEOUT_SECONDS
    while time.time() < deadline:
        cmd = _read_command(conversation_id)
        if cmd is not None:
            resolved = _resolve(cmd, request_id)
            if resolved is not None:
                decision, reason = resolved
                _consume_command(conversation_id)
                break
        time.sleep(_POLL_INTERVAL_SECONDS)

    for key in ("pending", "request_id", "tool_name", "target"):
        record.pop(key, None)
    cas.write_record(conversation_id, record)

    if decision == "deny":
        _deny(reason or "Denied from Perch")
    # allow or timeout -> fail open (Cursor proceeds).
    _allow()


if __name__ == "__main__":
    main()
    sys.exit(0)
