#!/bin/bash
# PermissionDenied hook: append each AUTO-MODE CLASSIFIER denial (time, session dir, tool, short command) to a log, so
# repeated blocks can be fixed once (an allow rule or environment entry, owner-approved) instead of re-asked in a pane.
# Per the docs this event fires only for classifier denials; hook denies (lane-guard) and deny rules don't reach it.
# Never blocks and never retries. Log: $DENIED_LOG (default ~/.claude/logs/denied.jsonl).
IN=$(cat)
log=${DENIED_LOG:-$HOME/.claude/logs/denied.jsonl}
mkdir -p "$(dirname "$log")"
printf '%s' "$IN" | jq -c --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{t:$t, cwd:(.cwd//""), tool:(.tool_name//""),
  cmd:((.tool_input.command // .tool_input.file_path // "")|tostring|.[0:200]), reason:(.reason // "")}' >> "$log" 2>/dev/null
exit 0
