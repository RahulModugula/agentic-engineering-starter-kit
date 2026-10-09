#!/bin/bash
# merge-guard.sh REPO PR SHA [MIN_CHECKS]
# Squash-merges REPO#PR only when its head is SHA, every check completed successfully (at least MIN_CHECKS), and
# GitHub reports it mergeable. Exit 0 = merged and read back as MERGED; 1 = refused or did not land.
# GH_ACCOUNT (optional): the gh account whose token to use, for machines with several logged-in accounts.
# Moved from a session scratchpad (2026-10-09); behaviour unchanged except POLL_TRIES/POLL_SLEEP for tests.
R=$1; P=$2; SHA=$3; MIN=${4:-3}
[ -n "$R" ] && [ -n "$P" ] && [ -n "$SHA" ] || { echo "usage: merge-guard.sh REPO PR SHA [MIN_CHECKS]" >&2; exit 2; }
# Exact sha only: a prefix could match a different commit pushed after the review.
printf '%s' "$SHA" | grep -Eq '^[0-9a-f]{40}$' || { echo "GUARD-REFUSED: give the full 40-character sha (got '$SHA')"; exit 1; }
case "$P" in ''|*[!0-9]*) echo "GUARD-REFUSED: PR must be a number (got '$P')"; exit 1;; esac
# At least one required check, as a whole number: "abc" would otherwise compare as 0 and allow zero checks.
case "$MIN" in ''|*[!0-9]*|0) echo "GUARD-REFUSED: minimum checks must be a whole number >= 1 (got '$MIN')"; exit 1;; esac
[ -n "${GH_ACCOUNT:-}" ] && { GH_TOKEN=$(gh auth token -u "$GH_ACCOUNT") || exit 1; export GH_TOKEN; }
TRIES=${POLL_TRIES:-45}; NAP=${POLL_SLEEP:-20}
for _ in $(seq 1 "$TRIES"); do
  j=$(gh pr view "$P" --repo "$R" --json headRefOid,statusCheckRollup,mergeable,mergeStateStatus) || { echo "GUARD: lookup failed"; exit 1; }
  head=$(jq -r .headRefOid <<<"$j")
  # EXPECTED = a required status that hasn't reported yet: wait for it rather than refuse.
  pend=$(jq '[.statusCheckRollup[]|select((.status//"COMPLETED")!="COMPLETED" or (.state//"")=="PENDING" or (.state//"")=="EXPECTED")]|length' <<<"$j")
  tot=$(jq '.statusCheckRollup|length' <<<"$j")
  ok=$(jq '[.statusCheckRollup[]|select(.conclusion=="SUCCESS" or .state=="SUCCESS")]|length' <<<"$j")
  [ "$pend" = 0 ] && [ "$tot" -ge "$MIN" ] && break
  sleep "$NAP"
done
echo "$R#$P head=${head:0:8} tot=$tot ok=$ok pend=$pend $(jq -r '.mergeable+" "+.mergeStateStatus' <<<"$j")"
ms=$(jq -r .mergeStateStatus <<<"$j")
# GitHub computes mergeability lazily: UNKNOWN right after a query means "not computed yet", so re-poll.
for _ in $(seq 1 12); do [ "$ms" = UNKNOWN ] || break; sleep "${POLL_RECHECK:-5}"; ms=$(gh pr view "$P" --repo "$R" --json mergeStateStatus -q .mergeStateStatus); done
# UNSTABLE = a non-required check failed; DRAFT = not ready. Both refuse.
case "$ms" in DIRTY|BLOCKED|BEHIND|UNKNOWN|UNSTABLE|DRAFT) echo "GUARD-REFUSED: mergeStateStatus=$ms"; exit 1;; esac
if [[ $head == "$SHA" && $pend == 0 && $ok == "$tot" && $tot -ge $MIN ]]; then
  gh pr merge "$P" --repo "$R" --squash --match-head-commit "$head" >/dev/null 2>&1; sleep "${POLL_RECHECK:-4}"
  res=$(gh pr view "$P" --repo "$R" --json state,mergeCommit --jq '"\(.state) \(.mergeCommit.oid)"'); echo "$res"
  [[ $res == MERGED* ]] || { echo "GUARD: merge did not land"; exit 1; }
else echo "GUARD-REFUSED"; exit 1; fi
