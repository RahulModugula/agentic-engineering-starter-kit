#!/bin/bash
# Stop: refuse "starting X…" endings while the lane state file has open items, and refuse a branch that changed only
# tests. Exits 0 when stop_hook_active (Claude Code caps Stop blocks at 8 in a row; don't fight it).
IN=$(cat)
[ "$(printf '%s' "$IN" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
CWD=$(printf '%s' "$IN" | jq -r '.cwd // ""'); MSG=$(printf '%s' "$IN" | jq -r '.last_assistant_message // ""')
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
F="$HOME/.claude/lanes/$(basename "$ROOT").md"
block() { jq -n --arg r "$1" '{decision:"block",reason:$r}'; exit 0; }
if [ -f "$F" ] && grep -q '^- \[ \]' "$F" && ! grep -q 'BLOCKED:' "$F"; then
  printf '%s' "$MSG" | tail -c 600 | grep -Eiq "(starting|kicking off|will now|next,? I'?ll|I'?ll now|moving on to|going to start)" \
    && block "You announced next work but stopped, and $F still has open '- [ ]' items. Do the next item now, or add a 'BLOCKED: <exact ask>' line to the state file and stop."
fi
B=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
case "$B" in main|master|HEAD) exit 0;; esac
CH=$(git -C "$ROOT" diff --name-only origin/main...HEAD 2>/dev/null)
[ -n "$CH" ] || exit 0
SRC=$(printf '%s\n' "$CH" | grep -Ev '(^|/)(tests?|__tests__|golden)/|\.test\.|\.spec\.|(^|/)test_[^/]*\.py$|_test\.py$|\.md$' | head -1)
[ -f "$F" ] && grep -q "TEST-ONLY-OK" "$F" && exit 0
[ -z "$SRC" ] && printf '%s\n' "$CH" | grep -Eq '(^|/)(tests?|__tests__)/|\.test\.|test_' \
  && block "This branch changes only test files vs origin/main ($B). If you weakened or deleted a test to get green, revert that and fix the code. If it's a genuine test-only PR, add a line TEST-ONLY-OK to your lane state file."
exit 0
