#!/bin/bash
# One full gate run, in its own throwaway worktree, on one exact commit. See docs/PARALLEL-LANES.md.
#
#   gate-isolated.sh <ref> <log-path>     run the gate; exit 0 only on a clean pass
#   gate-isolated.sh --self-check         prove, in a scratch repo, that a failing check makes this script fail
#
# The worktree is named after the log (gate.pr12.log -> <GATE_WT_DIR>/gate.pr12), so two runs never share one;
# if that worktree already exists the run refuses instead of reusing it. After the check, the worktree's HEAD and
# tracked files must be exactly as the gate left them; if anything moved them, the result is INVALID: rerun.
# The last line of the log is the verdict: "GATE PASS <sha>", "GATE FAIL <sha> rc=<n>" or "GATE INVALID <sha> ...".
#
# Settings (environment):
#   GATE_CMD         the repo's full check, run with sh from the worktree root (default: make check)
#   GATE_SETUP       optional commands run first, in the same shell, under set -e: a failing setup line fails
#                    the gate (e.g. activate an existing virtualenv)
#   GATE_MERGE_BASE  optional ref to merge into the commit before gating, e.g. origin/main (merge-up). A conflict
#                    stops the run (exit 3): resolve it on the branch, push, and gate the new head
#   GATE_REPO        the repository (default: the git repo of the current directory)
#   GATE_WT_DIR      where gate worktrees go (default: $TMPDIR/gate-worktrees)
#   GATE_KEEP=1      keep the worktree afterwards (it is removed by default)
# The check sees GATE_SHA (the commit under test, after any merge-up) and GATE_WORKTREE (its path).
# Exit: 0 pass, 1 check failed, 2 usage/setup error, 3 merge-up conflict, 4 invalid (worktree changed under it).
# bash 3.2 compatible.
set -u

die() { echo "gate-isolated: $*" >&2; exit 2; }

self_check() {
  local d rc_fail rc_pass
  d=$(mktemp -d "${TMPDIR:-/tmp}/gate-selfcheck.XXXXXX") || die "mktemp failed"
  git init -q "$d/repo" && git -C "$d/repo" -c user.name=gate -c user.email=gate@localhost \
    commit -q --allow-empty -m init || { rm -rf "$d"; die "self-check: git init failed"; }
  GATE_REPO="$d/repo" GATE_WT_DIR="$d/wt" GATE_CMD=false GATE_SETUP='' GATE_MERGE_BASE='' GATE_KEEP='' \
    /bin/bash "$0" HEAD "$d/fail.log" >/dev/null 2>&1; rc_fail=$?
  GATE_REPO="$d/repo" GATE_WT_DIR="$d/wt" GATE_CMD=true GATE_SETUP='' GATE_MERGE_BASE='' GATE_KEEP='' \
    /bin/bash "$0" HEAD "$d/pass.log" >/dev/null 2>&1; rc_pass=$?
  rm -rf "$d"
  if [ "$rc_fail" = 1 ] && [ "$rc_pass" = 0 ]; then
    echo "self-check ok: a failing check exits 1, a passing check exits 0"; exit 0
  fi
  echo "self-check FAILED: failing check exited $rc_fail (want 1), passing check exited $rc_pass (want 0)" >&2
  exit 1
}

[ "${1:-}" = "--self-check" ] && self_check
[ $# -eq 2 ] || die "usage: gate-isolated.sh <ref> <log-path> | --self-check"
REF=$1; LOG=$2
CMD=${GATE_CMD:-make check}
REPO=$(git -C "${GATE_REPO:-.}" rev-parse --show-toplevel 2>/dev/null) || die "not a git repository: ${GATE_REPO:-.}"
SHA=$(git -C "$REPO" rev-parse --verify -q "$REF^{commit}") || die "unknown ref: $REF"

name=$(basename "$LOG"); name=${name%.log}
case "$name" in ''|.|..) die "log path needs a file name: $LOG";; esac
WT_DIR=${GATE_WT_DIR:-${TMPDIR:-/tmp}/gate-worktrees}
mkdir -p "$WT_DIR" "$(dirname "$LOG")" || die "cannot create $WT_DIR or the log directory"
WT_DIR=$(cd "$WT_DIR" && pwd -P) || die "cannot enter $WT_DIR"
WT="$WT_DIR/$name"
[ -e "$WT" ] && die "worktree $WT already exists: one worktree per gate run, never shared (use a new log name)"
log() { echo "$*" >> "$LOG"; }
cleanup() {
  [ "${GATE_KEEP:-}" = 1 ] && return
  git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"
  git -C "$REPO" worktree prune >/dev/null 2>&1
}
verdict() { log "$1"; echo "$1"; }

git -C "$REPO" worktree add -q --detach "$WT" "$SHA" >&2 || die "worktree add failed: $WT"
trap cleanup EXIT
: > "$LOG" || die "cannot write $LOG"

log "gate: ref=$REF sha=$SHA worktree=$WT"
if [ -n "${GATE_MERGE_BASE:-}" ]; then
  BASE=$(git -C "$REPO" rev-parse --verify -q "${GATE_MERGE_BASE}^{commit}") || {
    verdict "GATE FAIL $SHA rc=2 (unknown merge base: $GATE_MERGE_BASE)"; exit 2; }
  if ! git -C "$WT" -c user.name=gate -c user.email=gate@localhost \
       merge -q --no-edit "$BASE" >> "$LOG" 2>&1; then
    verdict "GATE FAIL $SHA rc=3 (merge-up of $GATE_MERGE_BASE conflicts: resolve on the branch, push, gate again)"
    exit 3
  fi
  SHA_UNDER_TEST=$(git -C "$WT" rev-parse HEAD)
  MERGED=" (merged with $GATE_MERGE_BASE as $SHA_UNDER_TEST)"
  log "gate: merged $GATE_MERGE_BASE ($BASE); testing $SHA_UNDER_TEST"
else
  SHA_UNDER_TEST=$SHA; MERGED=
fi
log "gate: cmd=$CMD"
log "gate: start $(date -u +%Y-%m-%dT%H:%M:%SZ)"

(
  cd "$WT" || exit 2
  export GATE_SHA="$SHA_UNDER_TEST" GATE_WORKTREE="$WT"
  if [ -n "${GATE_SETUP:-}" ]; then
    /bin/sh -c "set -e
$GATE_SETUP
set +e
$CMD"
  else
    /bin/sh -c "$CMD"
  fi
) >> "$LOG" 2>&1
rc=$?
log "gate: end $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Did anything else move this worktree while the check ran? Untracked build output is fine; HEAD or tracked
# files changing means the result describes some other tree.
now=$(git -C "$WT" rev-parse HEAD 2>/dev/null)
dirty=$(git -C "$WT" status --porcelain --untracked-files=no 2>/dev/null | head -5)
if [ "$now" != "$SHA_UNDER_TEST" ] || [ -n "$dirty" ]; then
  verdict "GATE INVALID $SHA$MERGED rc=$rc (worktree changed during the run: HEAD=${now:-?}${dirty:+, tracked files changed}): rerun in a new worktree"
  exit 4
fi
if [ "$rc" = 0 ]; then
  verdict "GATE PASS $SHA$MERGED"
  exit 0
fi
verdict "GATE FAIL $SHA$MERGED rc=$rc"
exit 1
