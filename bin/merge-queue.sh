#!/bin/bash
# merge-queue.sh: guard-merge every ready PR in the queue file, one at a time, at its exact reported sha.
# Coordinator-only (lane-guard denies it elsewhere). Moved from a session scratchpad (2026-10-09).
#
# State lives OUTSIDE the script (the old version kept its queue in a heredoc that was edited while running, and
# bash reads scripts as it executes them):
#   $MERGE_STATE/queue.txt     lines "OWNER/REPO PR SHA [MIN_CHECKS]"; '#' comments a line out
#   $MERGE_STATE/verified.txt  lines "OWNER/REPO PR SHA" the coordinator recorded from the verifier's own message
#   $MERGE_STATE/post-merge.sh optional; run as `post-merge.sh REPO PR` after each merge (e.g. a tracker note)
#   $MERGE_STATE/deploy-busy.sh optional; `deploy-busy.sh REPO` exits 0 while a deploy for REPO is running
# Options (env): MERGE_STATE (default ~/.local/state/merge-queue), GH_ACCOUNT, REQUIRE_VERIFIED=1,
#   VERIFY_FROM="owner/repo=N ..." (PRs at or below N are grandfathered), URGENT=1 (skip the window),
#   MERGE_MODE=window (default: a repo opens at most once per WINDOW_MIN=45 minutes)
#   MERGE_MODE=green  (change 5, off by default: a repo opens when its main CI is green and no deploy is running;
#                      after a repo's batch lands, wait for main CI on the new head and stop that repo if it's red)
#   DRY_RUN=1          print what would merge; merge nothing.
#   REVIEW_TIERS=1     (default) for repos with a .review-tiers file on the base branch, a human-tier PR merges only
#                      after a person approves that exact sha: a line in $MERGE_STATE/human-approved.txt written by
#                      bin/human-approve.sh, or an APPROVED review at that commit by a login in HUMAN_REVIEWERS.
# Run from a private copy (bash reads a script as it runs, so an edit mid-run would corrupt it). Note our real
# directory first: the copy lives in a temp dir.
[ "${MQ_COPY:-}" = "$0" ] || { export MQ_HERE="${MQ_HERE:-$(cd "$(dirname "$0")" && pwd)}"; _c="$(mktemp "${TMPDIR:-/tmp}/mergeq.XXXXXX")" && cp "$0" "$_c" && MQ_COPY="$_c" exec /bin/bash "$_c" "$@"; }
HERE=$MQ_HERE
ST=${MERGE_STATE:-$HOME/.local/state/merge-queue}
Q=$ST/queue.txt; V=$ST/verified.txt
[ -f "$Q" ] || { echo "STOP: no queue file $Q"; exit 1; }
[ -n "${GH_ACCOUNT:-}" ] && { GH_TOKEN=$(gh auth token -u "$GH_ACCOUNT") || exit 1; export GH_TOKEN; }
MODE=${MERGE_MODE:-window}
vfrom() { local kv; for kv in ${VERIFY_FROM:-}; do [ "${kv%%=*}" = "$1" ] && { echo "${kv#*=}"; return; }; done; echo 0; }
# The CI workflow file per repo (green mode reads ONLY this workflow's push runs, never a deploy or cron run).
# CI_WORKFLOWS="owner/repo=ci.yml owner/other=test.yml"; default ci.yml.
ci_wf() { local kv; for kv in ${CI_WORKFLOWS:-}; do [ "${kv%%=*}" = "$1" ] && { echo "${kv#*=}"; return; }; done; echo ci.yml; }
main_ci() {  # main_ci REPO [SHA] -> "status conclusion" of the CI workflow's latest push run on main (at SHA if given)
  gh run list -R "$1" --branch main --workflow "$(ci_wf "$1")" --event push ${2:+--commit "$2"} --limit 1 \
    --json status,conclusion --jq '.[0]|"\(.status) \(.conclusion)"' 2>/dev/null
}

repo_open() {  # repo_open REPO -> 0 if the repo may take a batch now
  local R=$1
  [ "${URGENT:-0}" = 1 ] && return 0
  if [ "$MODE" = green ]; then
    if [ -x "$ST/deploy-busy.sh" ] && "$ST/deploy-busy.sh" "$R"; then echo "$R deploy running; held"; return 1; fi
    local c; c=$(main_ci "$R")
    [ "$c" = "completed success" ] || { echo "$R main CI ($(ci_wf "$R")) is '$c', not green; held"; return 1; }
    return 0
  fi
  local last age
  last=$(gh pr list -R "$R" --state merged --limit 30 --json mergedAt --jq 'map(.mergedAt)|max // ""')
  [ -n "$last" ] || return 0
  age=$(python3 -c "import datetime as d,sys;print(int((d.datetime.now(d.timezone.utc)-d.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))).total_seconds()))" "$last")  # portable (no BSD date)
  [ "$age" -ge $(( ${WINDOW_MIN:-45} * 60 )) ] && return 0
  echo "$R window closed: last merge $((age/60)) min ago (<${WINDOW_MIN:-45}); held for next window"; return 1
}

after_batch() {  # green mode: main CI on the new head must go green, else stop merging into that repo
  local R=$1 c sha
  # Pin the NEW head: reading "the latest run" straight after a merge can return the previous head's green run.
  sha=$(gh api "repos/$R/commits/main" --jq .sha 2>/dev/null)
  [ -n "$sha" ] || { echo "STOP: $R could not read main's head after the batch"; return 1; }
  for _ in $(seq 1 "${MAIN_CI_TRIES:-40}"); do
    c=$(main_ci "$R" "$sha")
    case "$c" in "completed success") echo "$R main CI green after batch (at ${sha:0:12})"; return 0;;
                 completed*) echo "STOP: $R main CI is '$c' after this batch (semantic conflict?). Fix forward first."; return 1;; esac
    sleep "${MAIN_CI_SLEEP:-30}"
  done
  echo "STOP: $R main CI did not finish"; return 1
}

OPEN=""; MERGED=""; RED=""
while read -r R P H N; do
  [ -z "$R" ] && continue; case "$R" in "#"*) continue;; esac
  # A malformed line is skipped loudly (a non-number PR used to make `-gt` error and skip the VERIFIED check).
  case "$P" in ''|*[!0-9]*) echo "SKIP malformed queue line: $R $P (PR must be a number)"; continue;; esac
  printf '%s' "$H" | grep -Eq '^[0-9a-f]{40}$' || { echo "SKIP malformed queue line: $R $P (need the full 40-char sha)"; continue; }
  case " $RED " in *" $R "*) echo "$R#$P skipped: $R main is red"; continue;; esac
  st=$(gh pr view "$P" -R "$R" --json state --jq .state 2>/dev/null)
  [ -n "$st" ] || { echo "STOP: state lookup failed for $R#$P (network?) - not guessing"; exit 1; }
  if [ "$st" = MERGED ]; then  # GitHub also marks a PR merged when its commits reach main another way
    echo "$R#$P already merged ($(gh pr view "$P" -R "$R" --json mergedBy,mergeCommit --jq '"by \(.mergedBy.login // "?") at \(.mergeCommit.oid // "?")"' 2>/dev/null)); check it if this queue didn't merge it"
    continue
  fi
  [ "$st" = OPEN ] || { echo "$R#$P is $st; skipped"; continue; }
  case " $OPEN " in *" $R "*) ;; *) repo_open "$R" || continue; OPEN="$OPEN $R";; esac
  if [ "${REQUIRE_VERIFIED:-1}" = 1 ] && [ "$P" -gt "$(vfrom "$R")" ]; then
    gh pr view "$P" -R "$R" --json comments --jq '.comments[].body' | grep -q "VERIFIED $H" \
      || { echo "$R#$P awaiting 'VERIFIED $H' comment from the verifier; skipped"; continue; }
    # Second key: the coordinator records the verifier's own message, because every session shares one GitHub account.
    grep -q "^$R $P $H\b" "$V" 2>/dev/null \
      || { echo "$R#$P has a VERIFIED comment but no coordinator record of the verifier's message; skipped"; continue; }
  fi
  # Human-review tier (on for any repo whose base branch has a .review-tiers file): core code waits for a person.
  if [ "${REVIEW_TIERS:-1}" = 1 ]; then
    tj=$(${REVIEW_TIER_CMD:-python3 $HERE/review_tier.py} --pr "$R" "$P" 2>/dev/null); trc=$?
    # Tiering is off ONLY when the checker says the base branch has no policy (an explicit false, never text).
    if ! jq -e '.policy_found == false' >/dev/null 2>&1 <<<"$tj"; then
      if [ $trc -ne 0 ]; then   # 10 = human, anything else = couldn't decide = human
        human_ok=0
        grep -q "^$R $P $H " "$ST/human-approved.txt" 2>/dev/null && human_ok=1
        if [ $human_ok = 0 ] && [ -n "${HUMAN_REVIEWERS:-}" ]; then
          for who in $(gh pr view "$P" -R "$R" --json reviews --jq ".reviews[] | select(.state==\"APPROVED\" and .commit.oid==\"$H\") | .author.login" 2>/dev/null); do
            case " $HUMAN_REVIEWERS " in *" $who "*) human_ok=1;; esac
          done
        fi
        if [ $human_ok = 0 ]; then
          echo "$R#$P NEEDS HUMAN REVIEW (core code): $(jq -r '.human_files|join(", ")' <<<"$tj" 2>/dev/null); skipped"
          echo "    approve after reading: ! $HERE/human-approve.sh $R $P $H"
          continue
        fi
        echo "$R#$P human review recorded at ${H:0:12}"
      fi
    fi
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then echo "DRY_RUN: would merge $R#$P at $H"; continue; fi
  GH_ACCOUNT="" /bin/bash "$HERE/merge-guard.sh" "$R" "$P" "$H" "${N:-3}" || { echo "STOP at $R#$P"; exit 1; }
  case " $MERGED " in *" $R "*) ;; *) MERGED="$MERGED $R";; esac
  [ -x "$ST/post-merge.sh" ] && { "$ST/post-merge.sh" "$R" "$P" || echo "WARNING: post-merge hook failed for $R#$P"; }
done < "$Q"

if [ "$MODE" = green ] && [ "${DRY_RUN:-0}" != 1 ]; then
  rc=0; for R in $MERGED; do after_batch "$R" || rc=1; done; exit $rc
fi
