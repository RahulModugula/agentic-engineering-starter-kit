#!/bin/bash
# Status line: model | repo:branch | context % | 5h and 7d plan usage | session cost estimate.
# Uses only documented status-line fields; missing fields are skipped (rate limits exist only on Pro/Max).
input=$(cat)
model=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
h5=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
d7=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0')
out="[$model]"
b=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) && out="$out $(basename "$(git -C "$dir" rev-parse --show-toplevel)"):$b"
out="$out ctx:${ctx}%"
[ "${ctx:-0}" -ge 70 ] 2>/dev/null && out="$out (consider /compact or /clear)"
[ -n "$h5" ] && out="$out 5h:${h5}%"
[ -n "$d7" ] && out="$out 7d:${d7}%"
printf '%s $%.2f est\n' "$out" "$cost"
