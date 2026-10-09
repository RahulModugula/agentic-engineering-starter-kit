#!/bin/bash
# PostToolUse(Bash), async: append one JSON line per command a session ran to ~/.claude/audit/tool-log.jsonl
# (AUDIT_LOG overrides), readable only by you. Fields: time (UTC), session, cwd, tool, command (first 500 chars,
# common secret formats masked). It never blocks or fails a session: any problem just skips the line.
# bin/measure.py and plain jq read it, e.g.: jq -r '.command' ~/.claude/audit/tool-log.jsonl | sort | uniq -c
LOG=${AUDIT_LOG:-$HOME/.claude/audit/tool-log.jsonl}
command -v jq >/dev/null 2>&1 || exit 0
umask 077
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
IN=$(cat)
cmd=$(printf '%s' "$IN" | jq -r '.tool_input.command // ""' 2>/dev/null | cut -c1-500 | perl -pe '
  s/\b(gh[pousr]_|github_pat_)[A-Za-z0-9_]{10,}/$1***/g;
  s/\b(AKIA|ASIA)[A-Z0-9]{12,}/$1***/g;
  s/\b(sk-(?:ant-|proj-)?)[A-Za-z0-9_-]{10,}/$1***/g;
  s/\b(xox[abposr]-)[A-Za-z0-9-]{10,}/$1***/g;
  s/(Bearer\s+)\S+/$1***/gi;
  s/((?:password|passwd|secret|token|api[_-]?key)\s*[=:]\s*)\S+/$1***/gi;
  s#(://[^/\s:@]+:)[^@\s]+@#$1***@#g;
' 2>/dev/null) || exit 0
printf '%s' "$IN" | jq -c --arg cmd "$cmd" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{ts:$ts, session:(.session_id // ""), cwd:(.cwd // ""), tool:(.tool_name // ""), command:$cmd}' \
  >> "$LOG" 2>/dev/null
exit 0
