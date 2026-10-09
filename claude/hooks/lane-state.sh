#!/bin/bash
# SessionStart(compact|resume): re-inject this lane's state file so nothing is lost at a compaction.
# File: ~/.claude/lanes/<git toplevel basename>.md (the lane keeps it current).
IN=$(cat); CWD=$(printf '%s' "$IN" | jq -r '.cwd // ""')
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
F="$HOME/.claude/lanes/$(basename "$ROOT").md"
[ -f "$F" ] || { echo "No lane state file at $F. Create it now: ticket, branch, PR+sha, '- [ ]' open items, approvals granted (scope), running jobs (PID + log)."; exit 0; }
echo "=== Lane state ($F), re-read after compact/resume ==="; cat "$F"
