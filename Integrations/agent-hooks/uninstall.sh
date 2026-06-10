#!/usr/bin/env bash
#
# Perch - remove the AI agent tracking hooks for Claude Code and Cursor.
#
# The inverse of install.sh. It deletes the hook scripts Perch copied into place and strips only
# Perch's entries from the Claude / Cursor hook configs (via _unmerge_hooks.py), leaving every other
# hook untouched. A .bak backup is written before either config is modified. Safe to run repeatedly.
#
# By default the per-session state directories are left in place (they are small and self-expire).
# Pass --purge-state to also remove them:
#
#   Integrations/agent-hooks/uninstall.sh [--purge-state]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
CURSOR_HOOKS_DIR="$HOME/.cursor/hooks"

PURGE_STATE=false
if [ "${1:-}" = "--purge-state" ]; then
    PURGE_STATE=true
fi

echo "Removing Perch agent-tracking hooks..."

# 1. Delete the copied hook scripts (only Perch's own files, by exact name).
for script in claude_agent_state.py claude_agent_gate.py; do
    rm -f "$CLAUDE_HOOKS_DIR/$script"
done
for script in cursor_agent_state.py cursor_agent_gate.py; do
    rm -f "$CURSOR_HOOKS_DIR/$script"
done
echo "  Removed hook scripts."

# 2. Strip Perch's entries from the hook configs idempotently (with backups).
python3 "$SCRIPT_DIR/_unmerge_hooks.py"

# 3. Optionally remove the per-session state + command directories.
if [ "$PURGE_STATE" = true ]; then
    rm -rf "$HOME/.claude/agent-tui-state" "$HOME/.cursor/agent-status"
    rm -rf "$HOME/.claude/agent-commands" "$HOME/.cursor/agent-commands"
    echo "  Purged state and command directories."
else
    echo "  Left state directories in place (pass --purge-state to remove them)."
fi

echo "Done."
echo "  - Claude Code stops running the hooks on newly started sessions."
echo "  - Cursor reloads hooks.json on save (restart Cursor if it doesn't pick up the change)."
