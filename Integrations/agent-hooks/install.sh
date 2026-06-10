#!/usr/bin/env bash
#
# Perch - install AI agent tracking hooks for Claude Code and Cursor.
#
# Idempotent and non-destructive: safe to run repeatedly. It copies the status-writer scripts into
# place and adds Perch's entries to the Claude Code / Cursor hook configs only if they're missing,
# backing up any existing config first. Existing hooks are preserved.
#
# Usage: Integrations/agent-hooks/install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
CURSOR_HOOKS_DIR="$HOME/.cursor/hooks"

echo "Installing Perch agent-tracking hooks..."

# 1. Copy the hook scripts into place (executable) and ensure the state + command dirs exist.
#    agent-commands/ is the return channel Perch writes decisions into for the Control feature.
mkdir -p "$CLAUDE_HOOKS_DIR" "$CURSOR_HOOKS_DIR"
mkdir -p "$HOME/.claude/agent-tui-state" "$HOME/.cursor/agent-status"
mkdir -p "$HOME/.claude/agent-commands" "$HOME/.cursor/agent-commands"
install -m 0755 "$SCRIPT_DIR/claude_agent_state.py" "$CLAUDE_HOOKS_DIR/claude_agent_state.py"
install -m 0755 "$SCRIPT_DIR/claude_agent_gate.py" "$CLAUDE_HOOKS_DIR/claude_agent_gate.py"
install -m 0755 "$SCRIPT_DIR/cursor_agent_state.py" "$CURSOR_HOOKS_DIR/cursor_agent_state.py"
install -m 0755 "$SCRIPT_DIR/cursor_agent_gate.py" "$CURSOR_HOOKS_DIR/cursor_agent_gate.py"
echo "  Copied hook scripts."

# 2. Merge the hook configs idempotently (with backups).
python3 "$SCRIPT_DIR/_merge_hooks.py"

echo "Done."
echo "  - Claude Code applies the new hooks to newly started sessions."
echo "  - Cursor reloads hooks.json on save (restart Cursor if it doesn't pick them up)."
