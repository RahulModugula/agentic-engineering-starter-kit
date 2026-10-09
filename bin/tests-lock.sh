#!/bin/bash
# tests-lock.sh on|off|status [REPO_DIR]: make a repo's test files read-only for Claude sessions (hooks/tests-lock.sh).
# Typical flow: a lane writes the tests and shows them failing; you run `tests-lock.sh on`; a lane implements until
# green; you run `tests-lock.sh off`. The lock file is ignored by git (a local workflow state, not a commit).
set -euo pipefail
cmd=${1:-status}; repo=$(git -C "${2:-.}" rev-parse --show-toplevel)
lock="$repo/.claude/tests-locked"
case "$cmd" in
  on)  mkdir -p "$repo/.claude"; date -u +%Y-%m-%dT%H:%M:%SZ > "$lock"
       # In a worktree .git is a file; ask git where the exclude file really lives.
       ex=$(git -C "$repo" rev-parse --git-path info/exclude); case "$ex" in /*) ;; *) ex="$repo/$ex";; esac
       mkdir -p "$(dirname "$ex")"
       grep -qx '.claude/tests-locked' "$ex" 2>/dev/null || echo '.claude/tests-locked' >> "$ex"
       echo "tests locked in $repo";;
  off) rm -f "$lock"; echo "tests unlocked in $repo";;
  status) [ -f "$lock" ] && echo "locked since $(cat "$lock")" || echo "unlocked";;
  *) echo "usage: tests-lock.sh on|off|status [REPO_DIR]" >&2; exit 2;;
esac
