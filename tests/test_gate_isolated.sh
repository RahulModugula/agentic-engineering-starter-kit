#!/bin/bash
# scripts/gate-isolated.sh: a failing check fails the gate, a passing one passes, the verdict names the exact sha,
# worktrees are never shared, merge-up conflicts stop the run, and a worktree changed under the run is INVALID.
. "$(dirname "$0")/lib.sh"
G="$ROOT/scripts/gate-isolated.sh"
R="$TMP/repo"; W="$TMP/wt"
gitc() { git -C "$R" -c user.name=t -c user.email=t@example.com "$@"; }
git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" checkout -q -b main; }
echo one > "$R/a.txt"; gitc add a.txt; gitc commit -q -m one
SHA=$(git -C "$R" rev-parse HEAD)
gate() { GATE_REPO="$R" GATE_WT_DIR="$W" GATE_SETUP='' GATE_MERGE_BASE='' GATE_KEEP='' /bin/bash "$G" "$@"; }

# Pass and fail, with the full sha in the verdict line.
GATE_CMD=true gate HEAD "$TMP/logs/pass.log" >/dev/null 2>&1; eq "passing check exits 0" "$?" "0"
eq "pass verdict names the full sha" "$(tail -1 "$TMP/logs/pass.log")" "GATE PASS $SHA"
GATE_CMD='exit 7' gate HEAD "$TMP/logs/fail.log" >/dev/null 2>&1; eq "failing check exits 1" "$?" "1"
eq "fail verdict names sha and rc" "$(tail -1 "$TMP/logs/fail.log")" "GATE FAIL $SHA rc=7"
GATE_CMD='echo hello-from-check' gate HEAD "$TMP/logs/out.log" >/dev/null 2>&1
ok "check output goes to the log" grep -q hello-from-check "$TMP/logs/out.log"
eq "worktree removed after the run" "$([ -e "$W/pass" ] && echo left || echo gone)" "gone"

# The check runs inside the worktree, at the commit under test, with GATE_SHA set; GATE_SETUP shares its shell.
GATE_CMD='test "$(git rev-parse HEAD)" = "$GATE_SHA" && test "$PWD" = "$GATE_WORKTREE" && test "$X" = 1' \
  GATE_REPO="$R" GATE_WT_DIR="$W" GATE_SETUP='X=1' /bin/bash "$G" HEAD "$TMP/logs/env.log" >/dev/null 2>&1
eq "check runs in the worktree with GATE_SHA and the setup's variables" "$?" "0"

# A failing setup line fails the gate even when the check itself would pass.
GATE_CMD=true GATE_REPO="$R" GATE_WT_DIR="$W" GATE_SETUP='false
X=1' /bin/bash "$G" HEAD "$TMP/logs/setup.log" >/dev/null 2>&1
eq "a failing setup line fails the gate" "$?" "1"

# Usage errors.
rc 2 "missing arguments is a usage error" gate HEAD
rc 2 "unknown ref is refused" env GATE_CMD=true GATE_REPO="$R" GATE_WT_DIR="$W" /bin/bash "$G" no-such-ref "$TMP/logs/x.log"

# One worktree per gate run: an existing one is refused, never reused.
mkdir -p "$W/shared"
rc 2 "an existing worktree is refused" env GATE_CMD=true GATE_REPO="$R" GATE_WT_DIR="$W" /bin/bash "$G" HEAD "$TMP/logs/shared.log"
rm -rf "$W/shared"

# A check whose tree is changed under it (another checkout in the same worktree) is INVALID, even if it "passed".
GATE_CMD='echo changed > a.txt' gate HEAD "$TMP/logs/moved.log" >/dev/null 2>&1; eq "tracked change during run is invalid" "$?" "4"
ok "invalid verdict says rerun" grep -q '^GATE INVALID .*rerun' "$TMP/logs/moved.log"
GATE_CMD='git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m x' gate HEAD "$TMP/logs/head.log" >/dev/null 2>&1
eq "HEAD moved during run is invalid" "$?" "4"
GATE_CMD='echo build > out.tmp' gate HEAD "$TMP/logs/untracked.log" >/dev/null 2>&1
eq "untracked build output is fine" "$?" "0"

# Merge-up: main is merged in before the check; a conflict stops the run.
gitc checkout -q -b feature; echo feat > "$R/f.txt"; gitc add f.txt; gitc commit -q -m feat
gitc checkout -q main; echo base > "$R/b.txt"; gitc add b.txt; gitc commit -q -m base
FEAT=$(git -C "$R" rev-parse feature)
GATE_CMD='test -f b.txt && test -f f.txt' GATE_MERGE_BASE=main GATE_REPO="$R" GATE_WT_DIR="$W" \
  /bin/bash "$G" feature "$TMP/logs/merge.log" >/dev/null 2>&1
eq "merge-up brings main in before the check" "$?" "0"
ok "merged verdict names the branch head" grep -q "^GATE PASS $FEAT (merged with main as " "$TMP/logs/merge.log"
gitc checkout -q feature; echo mine > "$R/a.txt"; gitc commit -q -am mine
gitc checkout -q main; echo theirs > "$R/a.txt"; gitc commit -q -am theirs
GATE_CMD=true GATE_MERGE_BASE=main GATE_REPO="$R" GATE_WT_DIR="$W" /bin/bash "$G" feature "$TMP/logs/conflict.log" >/dev/null 2>&1
eq "merge-up conflict stops the run" "$?" "3"

# The script's own self-check passes here.
ok "--self-check passes" /bin/bash "$G" --self-check
finish
