#!/usr/bin/env python3
"""
Claude Code agent-state writer (Perch).

Invoked by Claude Code hooks. Reads the hook payload on stdin and records a small status file at
``~/.claude/agent-tui-state/<session_id>.json`` so Perch can show whether this session is working,
waiting, or done. It only writes a status file and never blocks the agent (always exits 0).

Status is derived by Perch from the recorded ``hook_event_name`` (e.g. ``Stop`` -> done,
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


_BRANCH_UNSAFE = re.compile(r"[^A-Za-z0-9._/-]")
_BRANCH_MAX = 40


def _git_branch(cwd: str) -> str:
    """Best-effort current git branch for ``cwd``.

    Read directly from git metadata (``.git/HEAD``) rather than shelling out, so we never spawn a
    subprocess on a hook-supplied value (Secure Python rule #6). ``cwd`` is the agent's own local
    working directory from the trusted hook payload, not remote input; we still validate it is an
    existing directory and only ever read the well-known, fixed ``HEAD`` metadata file under it
    (never write, never execute) before sanitizing the result (rules #1/#2). Returns "" on any miss.
    """
    try:
        if not cwd or not os.path.isdir(cwd):
            return ""
        git_path = Path(cwd) / ".git"
        if git_path.is_file():
            # Worktree / submodule: ``.git`` is a file pointing at the real git dir.
            text = git_path.read_text(encoding="utf-8", errors="ignore").strip()
            if text.startswith("gitdir:"):
                git_dir = Path(text.split(":", 1)[1].strip())
            else:
                return ""
        else:
            git_dir = git_path
        head = (git_dir / "HEAD").read_text(encoding="utf-8", errors="ignore").strip()
        if head.startswith("ref:"):
            ref = head.split(":", 1)[1].strip()
            name = ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref
        else:
            name = head[:7]  # detached HEAD -> short sha
        return _BRANCH_UNSAFE.sub("", name)[:_BRANCH_MAX]
    except (OSError, ValueError):
        return ""


def _pretty_model(raw: str) -> str:
    """Map a verbose model id (e.g. ``claude-3-5-sonnet-20241022``) to a short family label."""
    low = raw.lower()
    for family in ("opus", "sonnet", "haiku"):
        if family in low:
            return family.capitalize()
    return raw[:24]


def _model_and_tokens(payload: dict) -> tuple[str, int]:
    """Best-effort (model label, latest-turn token count) from the session transcript.

    ``transcript_path`` is a local JSONL file Claude Code maintains; we read only its tail and parse
    the most recent assistant entry for its model + usage. Returns ("", 0) on any miss so a missing
    or changed transcript format simply omits the (optional, hover-only) detail.
    """
    path = payload.get("transcript_path")
    if not isinstance(path, str) or not path or not os.path.isfile(path):
        return "", 0
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - 65536))
            chunk = handle.read().decode("utf-8", errors="ignore")
    except OSError:
        return "", 0
    for line in reversed(chunk.splitlines()):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if not isinstance(obj, dict) or obj.get("type") != "assistant":
            continue
        message = obj.get("message")
        if not isinstance(message, dict):
            continue
        model = message.get("model")
        if not isinstance(model, str) or not model:
            continue
        usage = message.get("usage") if isinstance(message.get("usage"), dict) else {}
        tokens = 0
        for key in ("input_tokens", "output_tokens",
                    "cache_creation_input_tokens", "cache_read_input_tokens"):
            value = usage.get(key)
            if isinstance(value, int) and value > 0:
                tokens += value
        return _pretty_model(model), tokens
    return "", 0


def _tty() -> str:
    """Best-effort controlling tty so the app can refocus the exact terminal tab. stdin is the
    hook payload pipe, so probe stdout/stderr instead. Failures are non-fatal."""
    for fd in (1, 2, 0):
        try:
            return _sanitize_focus(os.ttyname(fd))
        except OSError:
            continue
    return ""


def read_payload() -> dict:
    """Reads and normalizes the hook payload from stdin. Always returns a dict."""
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, OSError):
        payload = {}
    return payload if isinstance(payload, dict) else {}


def build_record(payload: dict) -> tuple[str, dict]:
    """Builds the (sanitized session id, status record) pair Perch reads. Shared by the plain state
    writer and the PreToolUse gate so both emit an identical monitoring shape."""
    session_id = _sanitize(str(payload.get("session_id", "unknown")))
    event = str(payload.get("hook_event_name", ""))
    env = os.environ
    cwd = str(payload.get("cwd", ""))
    model, tokens = _model_and_tokens(payload)
    record = {
        "session_id": session_id,
        "hook_event_name": event,
        "cwd": cwd,
        "git_branch": _git_branch(cwd),
        "model": model,
        "tokens": tokens,
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
    return session_id, record


def write_record(session_id: str, record: dict) -> None:
    """Atomically writes a session's status file. Best-effort: never raises (a status write must
    never break the hook). `session_id` is the already-sanitized value from `build_record`."""
    state_dir = Path.home() / ".claude" / "agent-tui-state"
    record["ts"] = time.time()
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        # Atomic write (temp file + os.replace) so Perch never reads a half-written file.
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


def main() -> None:
    payload = read_payload()
    session_id, record = build_record(payload)
    write_record(session_id, record)


if __name__ == "__main__":
    main()
    sys.exit(0)
