#!/bin/bash
# PreToolUse(Edit|Write|NotebookEdit): while the repo has a `.claude/tests-locked` file, test files are read-only.
# Use it for the implement step: one session writes the tests and sees them fail, you lock them, another session
# implements until they pass. A measured result (ImpossibleBench, arXiv 2510.20270): read-only tests keep real
# performance and stop agents editing tests to get green.
# Toggle with bin/tests-lock.sh on|off|status. Bash writes to tests are caught by the review tier (it escalates
# deleted or weakened tests), not here.
IN=$(cat)
f=$(printf '%s' "$IN" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')
[ -n "$f" ] || exit 0
cwd=$(printf '%s' "$IN" | jq -r '.cwd // ""')
case "$f" in /*) ;; *) f="$cwd/$f";; esac
root=$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null || git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/.claude/tests-locked" ] || exit 0
rel=${f#"$root"/}
case "$f" in */.claude/tests-locked) rel=.claude/tests-locked;; esac   # suffix match: /var vs /private/var paths
[ "$rel" = .claude/tests-locked ] && { jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"The test lock is the owner'"'"'s to change (tests-lock)."}}'; exit 0; }
if printf '%s' "$rel" | grep -Eq '(^|/)(tests?|__tests__|spec|__snapshots__|golden)/|(^|/)test_[^/]*\.py$|_test\.(py|go)$|\.(test|spec)\.[jt]sx?$|\.snap$'; then
  jq -n --arg r "Tests are locked in this repo (.claude/tests-locked): implement until they pass; don't edit them. If a test is wrong, stop and say so." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
exit 0
