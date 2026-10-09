#!/bin/bash
# Notification hook: a macOS notification when a session waits on you (permission prompt or idle), so a pane that
# needs a go doesn't sit unseen. Observational only; it never blocks. Set NOTIFY_OFF=1 to silence.
IN=$(cat)
[ "${NOTIFY_OFF:-0}" = 1 ] && exit 0
type=$(printf '%s' "$IN" | jq -r '.notification_type // "notice"')
msg=$(printf '%s' "$IN" | jq -r '.message // "Claude needs your attention"' | tr -d '"\\' | cut -c1-180)
dir=$(printf '%s' "$IN" | jq -r '.cwd // ""'); dir=${dir##*/}
title="Claude: ${dir:-session} ($type)"
if [ -n "${NOTIFY_CMD:-}" ]; then "$NOTIFY_CMD" "$title" "$msg"
elif command -v osascript >/dev/null 2>&1; then osascript -e "display notification \"$msg\" with title \"$title\"" >/dev/null 2>&1
elif command -v notify-send >/dev/null 2>&1; then notify-send "$title" "$msg" >/dev/null 2>&1   # Linux
else printf '\a' > /dev/tty 2>/dev/null; fi                                                        # terminal bell

exit 0
