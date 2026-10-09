#!/bin/bash
# Test lock: while locked, Edit/Write to test files is denied and source files are allowed; sessions can't lift it.
. "$(dirname "$0")/lib.sh"
H=$ROOT/claude/hooks/tests-lock.sh
R=$TMP/repo; mkdir -p "$R/src" "$R/tests"; git -C "$R" init -q -b main
d() {  # d TOOL FILE -> deny|allow
  local o; o=$(jq -n --arg t "$1" --arg f "$2" --arg c "$R" '{tool_name:$t,tool_input:{file_path:$f},cwd:$c}' | "$H")
  [ -z "$o" ] && echo allow || jq -r .hookSpecificOutput.permissionDecision <<<"$o"
}
eq "unlocked: tests are editable" "$(d Edit "$R/tests/test_a.py")" "allow"
/bin/bash "$ROOT/bin/tests-lock.sh" on "$R" >/dev/null
eq "locked: Edit on tests/ denied" "$(d Edit "$R/tests/test_a.py")" "deny"
eq "locked: Write to a new test file denied" "$(d Write "$R/src/a.test.ts")" "deny"
eq "locked: a snapshot is a test too" "$(d Edit "$R/src/__snapshots__/a.snap")" "deny"
eq "locked: relative path resolved against cwd" "$(d Edit "tests/test_b.py")" "deny"
eq "locked: source files stay editable" "$(d Edit "$R/src/app.py")" "allow"
eq "locked: the lock file itself can't be edited" "$(d Write "$R/.claude/tests-locked")" "deny"
# Through a symlinked path (git reports the resolved root, so a prefix strip fails): still protected, on any OS.
ln -s "$R" "$TMP/via-link"
eq "locked: lock file via a symlinked path can't be edited" "$(d Write "$TMP/via-link/.claude/tests-locked")" "deny"
ok "lock file is excluded from git" grep -qx '.claude/tests-locked' "$R/.git/info/exclude"
ok "status reports locked" grep -q locked <<<"$(/bin/bash "$ROOT/bin/tests-lock.sh" status "$R")"
/bin/bash "$ROOT/bin/tests-lock.sh" off "$R" >/dev/null
eq "after unlock: tests editable again" "$(d Edit "$R/tests/test_a.py")" "allow"
eq "a file outside any git repo: allowed" "$(d Edit "/tmp/x-$$.py")" "allow"
# Review finding: inside a git worktree (.git is a file) `on` must succeed and keep the lock out of git status.
git -C "$R" -c user.email=t@example.test -c user.name=t commit -q --allow-empty -m base
git -C "$R" worktree add -q "$TMP/wt" -b wt 2>/dev/null
rc 0 "tests-lock on works inside a worktree" /bin/bash "$ROOT/bin/tests-lock.sh" on "$TMP/wt"
eq "the lock file doesn't show up as untracked in the worktree" "$(git -C "$TMP/wt" status --porcelain)" ""
# Sessions can't lift or set the lock (lane-guard)
printf 'COORD_DIR=%s\n' "$TMP/coord" > "$TMP/g.conf"
gd() { local o; o=$(jq -n --arg c "$1" --arg d "$R" '{tool_input:{command:$c},cwd:$d}' | GUARD_CONF=$TMP/g.conf "$ROOT/claude/hooks/lane-guard.sh"); [ -z "$o" ] && echo allow || jq -r .hookSpecificOutput.permissionDecision <<<"$o"; }
eq "session can't run tests-lock.sh" "$(gd 'bash ~/kit/bin/tests-lock.sh off')" "deny"
eq "session can't delete the lock" "$(gd 'rm -f .claude/tests-locked')" "deny"
eq "session can't overwrite the lock" "$(gd 'cat x > .claude/tests-locked')" "deny"
eq "session may read the lock" "$(gd 'cat .claude/tests-locked')" "allow"
finish
