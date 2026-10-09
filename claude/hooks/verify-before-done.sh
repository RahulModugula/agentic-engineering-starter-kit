#!/bin/bash
# Stop hook: "done" must mean the project's checks pass, not that Claude said so.
# Runs the repo's check command when files changed since the last PASSING run, and blocks the turn (exit 2) on red.
# The check command, first one found:
#   1. .claude/check            (an executable you write: the fastest meaningful checks for this repo)
#   2. `make check`             (if the Makefile has a check target)
#   3. `npm test --silent`      (if package.json has a test script)
# Safety: it only runs a repo's own check code if you've trusted that repo (bin/trust-repo.sh adds it to
# ~/.claude/trusted-repos), so cloning an untrusted repo can't run its code just because a session ended there.
# Cheap when nothing changed: the dirty set is fingerprinted, and only a passing run is remembered.
IN=$(cat)
[ "$(printf '%s' "$IN" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0   # never loop
CWD=$(printf '%s' "$IN" | jq -r '.cwd // ""'); SID=$(printf '%s' "$IN" | jq -r '.session_id // "nosession"')
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
TRUST=${TRUSTED_REPOS_FILE:-$HOME/.claude/trusted-repos}
MAIN=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')
grep -qxF "$ROOT" "$TRUST" 2>/dev/null || grep -qxF "${MAIN:-/nonexistent}" "$TRUST" 2>/dev/null || exit 0
cd "$ROOT" || exit 0
if [ -x .claude/check ]; then CMD=(./.claude/check)
elif [ -f Makefile ] && grep -q '^check:' Makefile; then CMD=(make -s check)
elif [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then CMD=(npm test --silent)
else exit 0; fi
DIRTY=$(git status --porcelain --untracked-files=all 2>/dev/null)
# Committed-but-unpushed work counts too: a session that commits and then stops must still pass the checks.
UNPUSHED=$(git rev-list -n1 HEAD --not --remotes 2>/dev/null)
[ -n "$DIRTY" ] || [ -n "$UNPUSHED" ] || exit 0
HEADSHA=$(git rev-parse -q --verify HEAD 2>/dev/null)
FP=$( { echo "HEAD $HEADSHA"; printf '%s\n' "$DIRTY" | cut -c4- | while read -r f; do [ -f "$f" ] && { printf '%s ' "$f"; cksum < "$f"; }; done; } | cksum | cut -d' ' -f1)
SD="$HOME/.claude/hooks/.state"; mkdir -p "$SD"; ST="$SD/verify-$SID-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
[ "$(cat "$ST" 2>/dev/null)" = "$FP" ] && exit 0
OUT=$("${CMD[@]}" 2>&1); RC=$?
if [ $RC -ne 0 ]; then
  echo "The project's checks fail on your changes (${CMD[*]}). Fix them before finishing:" >&2
  printf '%s\n' "$OUT" | tail -25 >&2
  exit 2   # block the turn
fi
printf '%s' "$FP" > "$ST"   # remember only a PASSING state
exit 0
