#!/bin/bash
# Stop hook: "done" must mean the project's checks pass, not that Claude said so.
# Runs the repo's check command when files changed since the last PASSING run, and blocks the turn (exit 2) on red.
# The check command, first one found:
#   1. .claude/check            (an executable you write: the fastest meaningful checks for this repo)
#   2. `make check`             (if the Makefile has a check target)
#   3. `npm test --silent`      (if package.json has a test script)
# TRUST CAVEAT: this hook EXECUTES the repo's own check command, so it only runs in repos listed in
# ~/.claude/trusted-repos (bin/trust-repo.sh adds one); cloning an untrusted repo can't run its code just because a
# session ended there.
# Cheap when nothing changed: the tree's content (HEAD, `git diff HEAD`, untracked files) is fingerprinted, and only
# a passing run is remembered.
# Retry cap: after VERIFY_MAX_BLOCKS (default 3) consecutive blocks on the same fingerprint, the stop is allowed with
# a notice that the checks still fail and a person should look, so a session can't loop forever. A pass or any edit
# resets the count.
IN=$(cat)
[ "$(printf '%s' "$IN" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0   # never loop
CWD=$(printf '%s' "$IN" | jq -r '.cwd // ""'); SID=$(printf '%s' "$IN" | jq -r '.session_id // "nosession"')
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
TRUST=${TRUSTED_REPOS_FILE:-$HOME/.claude/trusted-repos}
MAIN=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')
grep -qxF "$ROOT" "$TRUST" 2>/dev/null || grep -qxF "${MAIN:-/nonexistent}" "$TRUST" 2>/dev/null || exit 0
cd "$ROOT" || exit 0
# On a branch, .claude/check runs as committed on the main branch: a session can't pass the gate by editing the
# check (a blocked session was seen rewriting it to `exit 0`). Changes to it apply once they merge.
BASEREF=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
for b in main master; do [ -n "$BASEREF" ] || { git rev-parse -q --verify "refs/heads/$b" >/dev/null && BASEREF=$b; }; done
CUR=$(git symbolic-ref -q --short HEAD 2>/dev/null)
NOTE=""
if [ -n "$BASEREF" ] && [ "$CUR" != "${BASEREF#origin/}" ] && git cat-file -e "$BASEREF:.claude/check" 2>/dev/null; then
  SD0="$HOME/.claude/hooks/.state"; mkdir -p "$SD0"; BASECHECK="$SD0/check-base-$$"
  git show "$BASEREF:.claude/check" > "$BASECHECK" && chmod +x "$BASECHECK"
  trap 'rm -f "$BASECHECK"' EXIT
  CMD=("$BASECHECK")
  git diff --quiet "$BASEREF" -- .claude/check 2>/dev/null \
    || NOTE="(Ran the main branch's .claude/check; your branch's edits to it apply after they merge.)"
elif [ -x .claude/check ]; then CMD=(./.claude/check)
elif [ -f Makefile ] && grep -q '^check:' Makefile; then CMD=(make -s check)
elif [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then CMD=(npm test --silent)
else exit 0; fi
DIRTY=$(git status --porcelain --untracked-files=all 2>/dev/null)
# Committed-but-unpushed work counts too: a session that commits and then stops must still pass the checks.
UNPUSHED=$(git rev-list -n1 HEAD --not --remotes 2>/dev/null)
[ -n "$DIRTY" ] || [ -n "$UNPUSHED" ] || exit 0
HEADSHA=$(git rev-parse -q --verify HEAD 2>/dev/null)
BASE=${HEADSHA:-$(git hash-object -t tree /dev/null)}   # no commit yet: diff against the empty tree
# From content, not `git status` text (which quotes odd paths, so their edits went unseen).
FP=$( { echo "HEAD $HEADSHA"
        git diff --no-ext-diff --no-textconv --binary "$BASE" 2>/dev/null
        git ls-files -o --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do
          printf 'untracked %s\n' "$f"; [ -f "$f" ] && cksum < "$f"; done; } | cksum | cut -d' ' -f1)
SD="$HOME/.claude/hooks/.state"; mkdir -p "$SD"; ST="$SD/verify-$SID-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
[ "$(cat "$ST" 2>/dev/null)" = "$FP" ] && exit 0
OUT=$("${CMD[@]}" 2>&1); RC=$?
BL="$ST.blocks"   # "<fingerprint> <consecutive blocks on it>"
if [ $RC -ne 0 ]; then
  # No stray shell errors on stderr: Claude Code ends the turn instead of continuing when it sees one.
  BFP=; N=0; if [ -f "$BL" ]; then read -r BFP N < "$BL"; fi
  case "$N" in ''|*[!0-9]*) N=0;; esac
  [ "$BFP" = "$FP" ] || N=0
  if [ "$N" -ge "${VERIFY_MAX_BLOCKS:-3}" ]; then
    MSG="Checks still failing after $N blocked stops on the same state (${CMD[*]}) in ${ROOT##*/}; a person should look."
    echo "$MSG" >&2
    jq -n --arg m "$MSG" '{systemMessage:$m}'
    jq -n --arg m "$MSG" --arg d "$ROOT" '{notification_type:"checks_failing",message:$m,cwd:$d}' \
      | "$(dirname "$0")/notify.sh" >/dev/null 2>&1
    exit 0   # let the stop through: blocking again on the same state would loop forever
  fi
  printf '%s %s\n' "$FP" "$((N + 1))" > "$BL"
  echo "The project's checks fail on your changes. Fix them before finishing:" >&2
  [ -n "$NOTE" ] && echo "$NOTE" >&2
  printf '%s\n' "$OUT" | tail -25 >&2
  exit 2   # block the turn
fi
rm -f "$BL"
printf '%s' "$FP" > "$ST"   # remember only a PASSING state
exit 0
