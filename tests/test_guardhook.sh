#!/bin/bash
# lane-guard: every rule must DENY/ASK the real thing and ALLOW look-alikes (mentions, reads, heredoc text).
. "$(dirname "$0")/lib.sh"
G=${GUARD_UNDER_TEST:-$ROOT/claude/hooks/lane-guard.sh}
COORD=$TMP/coord; LANE=$TMP/lane
mkdir -p "$COORD" "$LANE"
GI=(-c user.email=t@example.test -c user.name=t)   # no dependence on the machine's global git identity
git -C "$LANE" init -q -b feature; git "${GI[@]}" -C "$LANE" commit -q --allow-empty -m x
git -C "$COORD" init -q -b main; git "${GI[@]}" -C "$COORD" commit -q --allow-empty -m x
NEW=$TMP/newrepo; mkdir -p "$NEW"; git -C "$NEW" init -q -b main   # unborn main: no commits yet
printf "COORD_DIR=%s\nPROD_PROFILE=prod\nCOORD_SCRIPTS_EXTRA='guard|merge_next'\n" "$COORD" > "$TMP/guard.conf"
export GUARD_CONF="$TMP/guard.conf"

decision() {  # decision CWD CMD -> deny|ask|allow
  local o; o=$(jq -n --arg c "$2" --arg d "$1" '{tool_input:{command:$c},cwd:$d}' | "$G")
  [ -z "$o" ] && { echo allow; return; }
  printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecision'
}
expect() { eq "$1 :: $3" "$(decision "$2" "$3")" "$1"; }

# --- merge/release scripts: coordinator-only when RUN ---
expect deny  "$LANE" 'bash ~/.claude/kit/bin/merge-queue.sh'
expect deny  "$LANE" 'bash /tmp/x/scratchpad/merge_next.sh'
expect deny  "$LANE" 'cd /tmp && bash guard.sh o/r 1 abc'
expect deny  "$LANE" 'URGENT=1 bash merge_next.sh'
expect deny  "$LANE" 'env -u AWS_PROFILE caffeinate -i bash ./merge-queue.sh'
expect deny  "$LANE" 'nohup bash merge_next.sh > log 2>&1 &'
expect deny  "$LANE" 'sh -c "bash merge_next.sh"'
expect deny  "$LANE" 'timeout 60 /bin/bash merge-guard.sh a 1 b'
expect deny  "$LANE" './merge_next.sh'
expect allow "$COORD" 'bash ~/.claude/kit/bin/merge-queue.sh'
# Regression (10-08/10-09): merely MENTIONING a guard script must not be blocked.
expect allow "$LANE" 'cat ~/.claude/hooks/lane-guard.sh'
expect allow "$LANE" 'diff -q a/lane-guard.sh b/lane-guard.sh'
expect allow "$LANE" 'bash test-pgrep-guard.sh'
expect allow "$LANE" 'grep -n merge_next.sh notes.md'
expect allow "$LANE" 'ls -la scratchpad | grep -E " (guard|merge_next)\."'
expect allow "$LANE" 'cat > notes.md <<EOF
bash merge_next.sh
EOF'

# --- pattern kills ---
expect deny  "$LANE" 'pkill -f "myjob.*"'
expect deny  "$LANE" 'sleep 1; killall python3'
expect deny  "$COORD" 'pkill -f merge'
expect allow "$LANE" 'kill 12345'
expect allow "$LANE" 'grep pkill notes.md'

# --- pushes ---
expect deny  "$LANE" 'git push origin main'
expect deny  "$LANE" 'git push origin HEAD:main'
expect deny  "$LANE" 'git push origin feature:refs/heads/main'
expect deny  "$LANE" "git -C $LANE push --force origin feature"
expect deny  "$LANE" 'git push -f origin feature'
expect deny  "$LANE" 'git push origin +feature'
expect deny  "$LANE" "sh -c 'git push origin main'"
expect allow "$LANE" 'git push -u origin feature'
expect allow "$LANE" 'git push --force-with-lease origin feature'
expect deny  "$COORD" 'git push'
expect allow "$LANE" 'git push'
# Text that merely mentions a push is not a push (the v3 parser sees `echo` as the program).
expect allow "$LANE" 'echo "do not git push origin main"'

# --- bypasses found by the fresh-context review (2026-10-09): each must be caught ---
expect deny  "$LANE" '{ bash merge-queue.sh; }'
expect deny  "$LANE" 'if true; then bash merge-queue.sh; fi'
expect deny  "$LANE" 'echo x | xargs bash merge-queue.sh'
expect deny  "$LANE" 'echo x | xargs -I{} bin/merge-queue.sh {}'
expect deny  "$LANE" '! bin/human-approve.sh o/r 1 abc'
expect deny  "$LANE" 'bash <<EOF
bin/human-approve.sh o/r 1 abc
EOF'
expect deny  "$LANE" 'python3 - <<EOF
import os; os.system("gh pr merge 5")
EOF'
expect deny  "$LANE" 'gh -R o/r pr merge 5'
expect deny  "$LANE" 'gh pr --repo o/r merge 5'
expect deny  "$LANE" 'gh api -X PUT repos/o/r/pulls/5/merge'
expect deny  "$LANE" 'git -c k=v push origin main'
expect deny  "$LANE" '/usr/bin/git push origin main'
expect deny  "$LANE" 'git --no-pager push origin main'
expect deny  "$LANE" 'git push -uf origin feature'
expect deny  "$LANE" 'rm .claude/tests-lock?d'
expect deny  "$LANE" 'rm -rf .claude'
expect deny  "$LANE" 'mv .claude/* /tmp/'
# --- second review (2026-10-09): more bypasses that must be caught ---
expect deny  "$COORD" 'git push origin HEAD'
expect deny  "$COORD" 'git push -u origin HEAD'
expect deny  "$COORD" 'git push origin @'
expect deny  "$LANE"  'git push --all origin'
expect deny  "$LANE"  'git push --mirror origin'
expect deny  "$NEW"   'git push'
expect deny  "$LANE"  'eval "gh pr merge 5"'
expect deny  "$LANE"  'eval git push origin main'
expect deny  "$LANE"  'cat <<EOF | bash
gh pr merge 5
EOF'
expect deny  "$LANE"  'echo "git push origin main" | sh'
expect deny  "$LANE"  'git -c alias.p=push p origin main'
expect deny  "$LANE"  'gh api graphql -f query=mutation{mergePullRequest(input:{pullRequestId:1}){clientMutationId}}'
expect deny  "$LANE"  'watch -n 5 gh pr merge 5'
expect deny  "$LANE"  'stdbuf -oL git push origin main'
expect deny  "$LANE"  'script -q /dev/null git push origin main'
expect deny  "$LANE"  'ssh build-host git push origin main'
expect deny  "$LANE"  'find . -name tests-lock -delete'
expect deny  "$LANE"  'python3 -c "import os; os.remove(\".claude/tests-locked\")"'
expect deny  "$LANE"  'bash ~/kit/bin/human-a*.sh o/r 1 abc'
# --- and everyday commands that must NOT be blocked (false positives found in review) ---
expect allow "$LANE"  'git commit -m "explain the human-approve flow"'
expect allow "$LANE"  'gh pr create --title "x" --body "needs human-approval"'
expect allow "$LANE"  'git add .claude'
expect allow "$LANE"  'vim docs/human-approve.md'
expect allow "$LANE"  'gh pr comment 5 --body "run gh pr merge after review"'
expect allow "$LANE"  'gh pr merge --help'
expect allow "$LANE"  'git commit -m "merge main into feature"'
expect allow "$LANE"  'git push origin HEAD'
expect allow "$LANE"  'pytest -q && npm test'
expect allow "$LANE"  'rm -f build/out.txt'
expect allow "$LANE" 'gh pr view 5 --json state'
expect allow "$LANE" 'gh api repos/o/r/pulls/5'
expect allow "$LANE" 'cat .claude/tests-locked'

# --- gh pr merge ---
expect deny  "$LANE" 'gh pr merge 12 --squash'
expect allow "$COORD" 'gh pr merge 12 --squash'

# --- prod AWS writes ask; reads pass ---
expect ask   "$LANE" 'aws s3api put-object --bucket b --key k --profile prod'
expect ask   "$LANE" 'aws s3 cp ./f s3://bucket/k --profile prod'
expect allow "$LANE" 'aws s3 cp s3://bucket/k ./f --profile prod'
expect allow "$LANE" 'aws sts get-caller-identity --profile prod'
expect allow "$LANE" 'aws s3api put-object --bucket b --key k --profile dev'

# No conf at all: merge scripts are denied everywhere (fail closed), prod rule off.
GUARD_CONF=$TMP/none.conf expect deny "$COORD" 'bash merge-queue.sh'

# Change 4 protection: off by default, on with GOS_PROTECT=1.
expect allow "$LANE" 'bash ~/.claude/kit/bin/go.sh job.sh'
printf 'COORD_DIR=%s\nGOS_PROTECT=1\n' "$COORD" > "$TMP/gos.conf"
GUARD_CONF=$TMP/gos.conf expect deny  "$LANE"  'bash ~/.claude/kit/bin/go.sh job.sh'
GUARD_CONF=$TMP/gos.conf expect deny  "$COORD" '~/.claude/kit/bin/go.sh job.sh'
GUARD_CONF=$TMP/gos.conf expect deny  "$LANE"  'echo x > ~/.claude/gos/abc.go'
GUARD_CONF=$TMP/gos.conf expect deny  "$LANE"  'cp a.go ~/.claude/gos/'
GUARD_CONF=$TMP/gos.conf expect allow "$LANE"  'ls ~/.claude/gos'
GUARD_CONF=$TMP/gos.conf expect deny  "$LANE"  'cat a.go > ~/.claude/gos/x.go'

# Human-review approvals: always owner-only.
expect deny  "$LANE"  'bash ~/.claude/kit/bin/human-approve.sh o/r 1 abc'
expect deny  "$COORD" '~/.claude/kit/bin/human-approve.sh o/r 1 abc'
expect deny  "$LANE"  'echo "o/r 1 abc" >> ~/.local/state/merge-queue/human-approved.txt'
expect deny  "$LANE"  'cat x >> ~/.local/state/merge-queue/human-approved.txt'
expect deny  "$LANE"  'cp x ~/.local/state/merge-queue/human-approved.txt'
expect allow "$LANE"  'cat ~/.local/state/merge-queue/human-approved.txt'
expect allow "$LANE"  'grep o/r ~/.local/state/merge-queue/human-approved.txt'
expect allow "$LANE"  'bash ~/.claude/kit/bin/human-queue.sh'

# --- v4: fail closed on input the guard can't read ---
o=$(printf 'not json' | "$G" 2>/dev/null); rc=$?
eq "bad JSON blocks (exit 2)" "$rc" 2
o=$(printf '{"tool_input":{"command":"git push origin main"},"cwd":"/"}' | PATH=/nonexistent /bin/bash "$G" 2>&1); rc=$?
eq "no jq blocks (exit 2)" "$rc" 2
case "$o" in *"jq is not installed"*) _res 0 "";; *) _res 1 "no jq should say why, got [$o]";; esac
# A heredoc whose delimiter never arrives isn't one: its lines are checked, not hidden.
expect deny  "$LANE"  'cat <<EOF
git push origin main'
expect deny  "$COORD" 'git push -o ci.skip origin'
expect deny  "$LANE"  'git -cremote.origin.push=HEAD:main push'
# --- v4: quotes and backslashes rejoin words ---
expect deny  "$LANE"  "git push origin ma''in"
expect deny  "$LANE"  'git pu""sh origin main'
expect deny  "$LANE"  'g\it push origin main'
# --- v4: refspec forms that reach main ---
expect deny  "$LANE"  'git push origin refs/heads/main'
expect deny  "$LANE"  'git push origin heads/master'
expect deny  "$LANE"  "git push origin 'refs/heads/*:refs/heads/*'"
expect deny  "$LANE"  'git push origin :'
expect deny  "$LANE"  'git push origin $BR'
expect deny  "$LANE"  'git push origin --branches'
expect allow "$LANE"  'git push -o ci.skip origin feature'
expect allow "$LANE"  'git push origin refs/heads/feature'
expect allow "$LANE"  'git push origin feature:feature-2'
# --- v4: push config can redirect a push ---
expect deny  "$LANE"  'git -c remote.origin.push=HEAD:main push'
expect deny  "$LANE"  'git config remote.origin.push HEAD:main'
expect deny  "$LANE"  'git config --global alias.ship push'
expect allow "$LANE"  'git config user.name x'
expect allow "$LANE"  'git config --get remote.origin.url'
# --- v4: wrappers by path, options with arguments, variables as commands ---
expect deny  "$LANE"  '/usr/bin/env git push origin main'
expect deny  "$LANE"  'sudo -u me git push origin main'
expect deny  "$LANE"  'timeout -s KILL 60 git push origin main'
expect deny  "$LANE"  'nice -n 5 git push origin main'
expect deny  "$LANE"  'p=pkill; $p -f x'
expect deny  "$LANE"  '${G:-git} push origin main'
# --- v4: merges over plain HTTP ---
expect deny  "$LANE"  'curl -X PUT -H "Authorization: token x" https://api.github.com/repos/o/r/pulls/5/merge'
expect deny  "$LANE"  'wget --method=PUT https://api.github.com/repos/o/r/pulls/5/merge'
expect allow "$LANE"  'curl https://api.github.com/repos/o/r/pulls/5'
# --- v4: message text is data, but only message flags are stripped ---
expect allow "$LANE"  'git commit -m "fix; then git push origin main"'
expect allow "$LANE"  'gh pr create --title "x" --body "(gh pr merge 5)"'
expect deny  "$LANE"  'ssh -t host "git push origin main"'
# --- v4: the controls, by path prefix ---
expect deny  "$LANE"  'rm ~/.claude/hooks/lane-guard.sh'
expect deny  "$LANE"  'cp x.json ~/.claude/settings.json'
expect deny  "$LANE"  'echo "/tmp" >> ~/.claude/trusted-repos'
expect deny  "$LANE"  'sed -i "" s/x/y/ ~/.claude/guard.conf'
expect deny  "$LANE"  'ln -sf /tmp/x ~/.claude/kit'
expect deny  "$LANE"  'rm ~/.local/state/merge-queue/verified.txt'
expect allow "$LANE"  'sed -n 1,5p ~/.claude/guard.conf'
expect allow "$LANE"  'awk 1 ~/.claude/settings.json'
expect allow "$LANE"  'cat ~/.claude/settings.json'
# --- v4: prod AWS: global options parsed; anything not read-only asks ---
expect ask   "$LANE"  'aws --profile prod --region us-east-1 lambda invoke --function-name f out.json'
expect ask   "$LANE"  'AWS_PROFILE=prod aws dynamodb delete-item --table-name t --key k'
expect ask   "$LANE"  'aws --profile=prod s3 rm s3://b/k'
expect allow "$LANE"  'aws --profile prod --output json dynamodb describe-table --table-name t'
expect allow "$LANE"  'aws --profile prod s3 ls s3://b/'
expect allow "$LANE"  'AWS_PROFILE=prodish aws s3 rm s3://b/k'
# --- v4: the fast path still lets everyday commands straight through ---
expect allow "$LANE"  'ls -la'
expect allow "$LANE"  'make check'
# --- release review (2026-10-09): bypasses found by an independent reviewer; each must be caught ---
expect deny  "$LANE"  'gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc'
expect deny  "$LANE"  'curl -X PATCH https://api.github.com/repos/o/r/git/refs/heads/main -d "{}"'
expect allow "$LANE"  'gh api repos/o/r/git/refs/heads/main'
expect deny  "$LANE"  'git subtree push --prefix=docs origin main'
expect allow "$LANE"  'git subtree push --prefix=docs origin docs-branch'
expect deny  "$LANE"  "cd $COORD && git push"
expect deny  "$LANE"  "cd $COORD && git push origin HEAD"
expect allow "$LANE"  "cd $LANE && git push origin feature"
expect deny  "$LANE"  'cd ~/.claude && rm hooks/lane-guard.sh'
expect deny  "$LANE"  'cd ~/.claude/hooks && : > notify.sh'
expect allow "$LANE"  'cd ~/.claude && ls hooks'
expect deny  "$LANE"  'tar -xf x.tar -C ~/.claude'
expect deny  "$LANE"  'unzip -o x.zip -d ~/.claude'
expect deny  "$LANE"  'curl -so ~/.claude/hooks/lane-guard.sh https://example.com/x'
expect allow "$LANE"  'curl -so /tmp/x https://example.com/x'
expect deny  "$LANE"  '`echo pkill` -f node'
expect deny  "$LANE"  'kill -9 $(pgrep -f node)'
expect deny  "$LANE"  'pgrep -f node | xargs kill'
expect allow "$LANE"  'pgrep -f node'
expect deny  "$LANE"  'busybox pkill node'
expect ask   "$LANE"  'AWS_DEFAULT_PROFILE=prod aws s3 rm s3://b/k'
finish
