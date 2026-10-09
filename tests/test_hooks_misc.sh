#!/bin/bash
# notify.sh and denied-log.sh: each must do its job on the right event and never block (always exit 0).
. "$(dirname "$0")/lib.sh"
H=$ROOT/claude/hooks
printf '#!/bin/bash\necho "$1|$2" >> %s/notes\n' "$TMP" > "$TMP/fake-notify"; chmod +x "$TMP/fake-notify"
echo '{"notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","cwd":"/x/my-app"}' \
  | NOTIFY_CMD="$TMP/fake-notify" "$H/notify.sh"; r=$?
eq "notify exits 0" "$r" "0"
ok "notify sends a notice naming the session and type" grep -q "Claude: my-app (permission_prompt)|Claude needs your permission" "$TMP/notes"
: > "$TMP/notes"
echo '{"notification_type":"idle_prompt"}' | NOTIFY_OFF=1 NOTIFY_CMD="$TMP/fake-notify" "$H/notify.sh"
eq "NOTIFY_OFF=1 silences it" "$(cat "$TMP/notes")" ""

echo '{"cwd":"/x/lane","tool_name":"Bash","tool_input":{"command":"gh run cancel 1"},"reason":"[Merge Without Review]"}' \
  | DENIED_LOG="$TMP/d.jsonl" "$H/denied-log.sh"; r=$?
eq "denied-log exits 0" "$r" "0"
eq "denied-log records tool and command" "$(jq -r '.tool+" "+.cmd' "$TMP/d.jsonl")" "Bash gh run cancel 1"
echo 'not json' | DENIED_LOG="$TMP/d2.jsonl" "$H/denied-log.sh"; r=$?
eq "denied-log never blocks on bad input" "$r" "0"

# audit-log.sh: one line per command, secrets masked, private file, never blocks.
A=$TMP/audit/log.jsonl
T1="ghp_""abcdefghijklmnop1234"; T2="AKIA""ABCDEFGHIJKLMNOP"
jq -n --arg c "curl -H 'Authorization: Bearer xyz123' https://x; export GH=$T1 K=$T2; mysql --password=hunter2" \
  '{session_id:"s1",cwd:"/w/lane",tool_name:"Bash",tool_input:{command:$c}}' | AUDIT_LOG="$A" "$H/audit-log.sh"; r=$?
eq "audit-log exits 0" "$r" "0"
eq "audit-log records session, cwd and tool" "$(jq -r '.session+" "+.cwd+" "+.tool' "$A")" "s1 /w/lane Bash"
c=$(jq -r .command "$A")
no "audit-log masks a GitHub token" grep -q "$T1" <<<"$c"
no "audit-log masks an AWS key id" grep -q "$T2" <<<"$c"
no "audit-log masks a bearer token" grep -q "xyz123" <<<"$c"
no "audit-log masks a password value" grep -q "hunter2" <<<"$c"
ok "audit-log keeps the command readable" grep -q "curl -H" <<<"$c"
eq "audit-log file is private (600)" "$(ls -l "$A" | cut -c1-10)" "-rw-------"
echo 'not json' | AUDIT_LOG="$A" "$H/audit-log.sh"; r=$?
eq "audit-log never blocks on bad input" "$r" "0"
finish
