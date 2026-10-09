#!/bin/bash
# End to end, offline: install this repo's claude/ into a throwaway HOME, then drive the INSTALLED hooks (through
# their symlinks) with the event JSON Claude Code sends, the way a real session would. Then roll back and prove
# the home is exactly as before. No model calls, no network.
. "$(dirname "$0")/lib.sh"
H=$TMP/home; CH=$H/.claude; mkdir -p "$CH" "$H/work"
printf '#!/bin/bash\necho "2.1.295 (Claude Code)"\n' > "$TMP/claude"; chmod +x "$TMP/claude"
export PATH="$TMP:$PATH"
(cd "$H" && find . -type f | sort | xargs shasum 2>/dev/null) > "$TMP/before.sha"
HOME=$H CLAUDE_HOME=$CH INSTALL_BACKUPS=$H/.claude-backups MERGE_STATE=$H/ms /bin/bash "$ROOT/install.sh" --apply >/dev/null
ok "install --apply succeeded and status is OK" env HOME=$H CLAUDE_HOME=$CH /bin/bash "$ROOT/install.sh" --status

# 1. Every hook/statusline command in the installed settings.json exists, is executable, and is a managed file.
cmds=$(jq -r '[.hooks[]?[]?.hooks[]?.command, .statusLine.command] | .[] | select(.)' "$CH/settings.json")
n=0; bad=""
while read -r c; do
  [ -z "$c" ] && continue; n=$((n + 1))
  p=$(printf '%s' "$c" | awk '{print $1}' | sed -e "s#^~#$H#" -e "s#^\$HOME#$H#" -e "s#^/Users/[^/]*/\.claude#$CH#")
  [ -x "$p" ] || bad="$bad $c"
done <<<"$cmds"
eq "all $n hook commands in settings.json resolve to installed executables" "${bad:-none}" "none"

hook() {  # hook NAME JSON -> runs the installed hook as Claude Code would (stdin JSON, HOME set)
  printf '%s' "$2" | HOME=$H "$CH/hooks/$1"
}
decision() {  # no output from a PreToolUse hook = allow
  local o; o=$(hook lane-guard.sh "$(jq -n --arg c "$1" --arg d "$2" '{tool_input:{command:$c},cwd:$d}')")
  [ -z "$o" ] && { echo allow; return; }
  printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}

# 2. The guard, through the installed copy, with the installed guard.conf.
L=$H/work/app/.claude/worktrees/lane-1; mkdir -p "$L"
git -C "$L" init -q -b lane-1; git -C "$L" -c user.email=t@example.test -c user.name=t commit -q --allow-empty -m x
eq "installed guard blocks a push to main" "$(decision 'git push origin main' "$L")" "deny"
eq "installed guard blocks pkill" "$(decision 'pkill -f job' "$L")" "deny"
eq "installed guard allows a feature-branch push" "$(decision 'git push -u origin lane-1' "$L")" "allow"
eq "installed guard blocks gh pr merge from a lane" "$(decision 'gh pr merge 3' "$L")" "deny"

# 3. Stop hook: runs only for a trusted repo; blocks a turn while the checks fail (every time, not just once);
#    lets it end when they pass; never loops.
R=$H/work/proj; mkdir -p "$R/.claude"; git -C "$R" init -q -b main
printf '#!/bin/bash\n! grep -q broken src.txt "my notes.txt" 2>/dev/null\n' > "$R/.claude/check"; chmod +x "$R/.claude/check"
echo broken > "$R/src.txt"
ev=$(jq -n --arg d "$R" '{cwd:$d,session_id:"s1",stop_hook_active:false}')
hook verify-before-done.sh "$ev" 2>/dev/null; eq "untrusted repo: its check code is NOT run (turn ends)" "$?" "0"
HOME=$H TRUSTED_REPOS_FILE=$CH/trusted-repos /bin/bash "$ROOT/bin/trust-repo.sh" "$R" >/dev/null
hook verify-before-done.sh "$ev" 2>"$TMP/first.err"; eq "trusted repo: Stop hook blocks (exit 2) while checks fail" "$?" "2"
# Found in a live Claude Code run: any stray shell error in the first block's stderr made Claude Code end the
# turn instead of continuing. The block message must be the first and only kind of line.
eq "first block's stderr starts with the block message" "$(head -1 "$TMP/first.err" | cut -c1-30)" "The project's checks fail on y"
no "first block's stderr carries no shell error" grep -q "No such file" "$TMP/first.err"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "and blocks AGAIN on the same red state (not just once)" "$?" "2"
echo fixed > "$R/src.txt"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "Stop hook lets the turn end when checks pass" "$?" "0"
echo broken > "$R/src.txt"
hook verify-before-done.sh "$(jq -n --arg d "$R" '{cwd:$d,session_id:"s1",stop_hook_active:true}')" 2>/dev/null
eq "Stop hook never loops (stop_hook_active)" "$?" "0"
# Review finding: committing the broken change, then stopping, must not escape the check.
git -C "$R" add -A; git -C "$R" -c user.email=t@example.test -c user.name=t commit -qm "broken, committed"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "committed-but-unpushed red work still blocks" "$?" "2"
# Retry cap: 3 consecutive blocks on the same state, then the stop is let through with a "person should look"
# notice, so a session can't loop forever. Any edit resets the count.
printf '#!/bin/bash\necho "$2" >> %s/vnotes\n' "$TMP" > "$TMP/vn.sh"; chmod +x "$TMP/vn.sh"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "same red state: 2nd block" "$?" "2"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "same red state: 3rd block" "$?" "2"
out=$(NOTIFY_CMD=$TMP/vn.sh hook verify-before-done.sh "$ev" 2>/dev/null); eq "after 3 blocks on one state, the stop is allowed" "$?" "0"
eq "the capped stop tells the user the checks still fail" "$(jq -r '.systemMessage | test("still failing")' <<<"$out")" "true"
ok "the capped stop sends a notification" grep -q "a person should look" "$TMP/vnotes"
echo "broken again" > "$R/src.txt"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "an edit resets the cap: red blocks again" "$?" "2"
# Fingerprint is the tree's CONTENT: a second edit to an already-dirty file with a space in its name (which
# `git status` quotes) must re-run the checks.
echo fixed > "$R/src.txt"; echo fine > "$R/my notes.txt"
git -C "$R" add -A; git -C "$R" -c user.email=t@example.test -c user.name=t commit -qm "fixed"
echo "fine 2" > "$R/my notes.txt"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "dirty spaced-name file, checks pass" "$?" "0"
echo broken > "$R/my notes.txt"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "editing that already-dirty file again re-runs the checks (blocks)" "$?" "2"
# Found in a live Claude Code run: a blocked session rewrote .claude/check to exit 0. On a branch, the check that
# runs is main's committed version; edits to it apply only after they merge (and .claude/** is human tier).
git -C "$R" checkout -q -- "my notes.txt"; git -C "$R" checkout -q -b lane-x
printf '#!/bin/bash\nexit 0\n' > "$R/.claude/check"; echo broken > "$R/src.txt"
hook verify-before-done.sh "$ev" 2>"$TMP/gm.err"; eq "a branch's own edit to .claude/check doesn't pass the gate" "$?" "2"
ok "…and the message says main's version ran" grep -q "main branch's .claude/check" "$TMP/gm.err"
git -C "$R" add -A; git -C "$R" -c user.email=t@example.test -c user.name=t commit -qm "game the check"
hook verify-before-done.sh "$ev" 2>/dev/null; eq "committing the edited check doesn't pass the gate either" "$?" "2"
git -C "$R" checkout -q main

# 4. SessionStart after compaction re-injects the lane state file.
mkdir -p "$CH/lanes"; printf -- '- [ ] write the login test\n' > "$CH/lanes/lane-1.md"
ok "lane state is re-injected after compaction" grep -q "write the login test" <<<"$(hook lane-state.sh "$(jq -n --arg d "$L" '{cwd:$d}')")"

# 5. Stop guard refuses "starting X..." endings while open items remain.
out=$(hook lane-stop-guard.sh "$(jq -n --arg d "$L" '{cwd:$d,stop_hook_active:false,last_assistant_message:"Done. Next, I will now start the API."}')")
eq "stop guard blocks an announced-but-not-started next step" "$(jq -r .decision <<<"$out")" "block"

# 6. Notification and denial log never block, and produce their output.
printf '#!/bin/bash\necho "$1" >> %s/notes\n' "$TMP" > "$TMP/n.sh"; chmod +x "$TMP/n.sh"
printf '%s' '{"notification_type":"permission_prompt","message":"needs you","cwd":"/w/app"}' | HOME=$H NOTIFY_CMD=$TMP/n.sh "$CH/hooks/notify.sh"
ok "notification fired" grep -q "Claude: app (permission_prompt)" "$TMP/notes"
hook denied-log.sh '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"},"reason":"r","cwd":"/w"}'
ok "denial logged under the installed home" test -s "$CH/logs/denied.jsonl"

# 7. Status line renders from documented fields.
sl=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":42.7},"cost":{"total_cost_usd":0.12}}' | HOME=$H "$CH/hooks/statusline.sh")
ok "status line shows the model" grep -q "Opus" <<<"$sl"

# 8. Roll back: the home is byte-for-byte as before (except the backup dir and test state we created).
rm -rf "$CH/lanes" "$CH/logs" "$CH/hooks/.state" "$CH/trusted-repos"
HOME=$H CLAUDE_HOME=$CH INSTALL_BACKUPS=$H/.claude-backups /bin/bash "$ROOT/install.sh" --rollback >/dev/null
(cd "$H" && find . -type f -not -path './.claude-backups/*' -not -path './work/*' -not -path './ms/*' | sort | xargs shasum 2>/dev/null) > "$TMP/after.sha"
ok "rollback restores the home exactly" cmp -s "$TMP/before.sha" "$TMP/after.sha"
eq "no symlinks left after rollback" "$(find "$CH" -type l | wc -l | tr -d ' ')" "0"
finish
