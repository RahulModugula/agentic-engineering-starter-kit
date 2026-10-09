#!/bin/bash
# human-queue.sh [--label] [--notify] [OWNER/REPO ...]: what is waiting on YOUR review, and exactly which files.
# For each open PR in the repos given (default: the repos in $MERGE_STATE/queue.txt), it runs review_tier.py and
# lists the human-tier PRs not yet approved at their current head, with the reasons and the files to read.
#   --label   add the `needs-human-review` label to those PRs (and remove it once approved)
#   --notify  one notification with the count: osascript (macOS), else notify-send (Linux), else a line on stderr
# Read-only on GitHub unless --label. Agents run it to flag; you run it to see your queue.
# "Approved" follows merge-queue.sh: with HUMAN_REVIEWERS set, an APPROVED GitHub review at the head sha by one of
# those logins (a human-approve.sh record counts only with ALLOW_LOCAL_APPROVALS=1); otherwise the local record.
HERE=$(cd "$(dirname "$0")" && pwd)
ST=${MERGE_STATE:-$HOME/.local/state/merge-queue}
RT=${REVIEW_TIER_CMD:-python3 $HERE/review_tier.py}
# human_approved REPO PR SHA: same rule as merge-queue.sh's human_approved. Keep the two in step.
human_approved() {
  if [ -z "${HUMAN_REVIEWERS:-}" ] || [ "${ALLOW_LOCAL_APPROVALS:-0}" = 1 ]; then
    grep -q "^$1 $2 $3 " "$ST/human-approved.txt" 2>/dev/null && return 0
  fi
  [ -n "${HUMAN_REVIEWERS:-}" ] || return 1
  gh api "repos/$1/pulls/$2/reviews" --paginate --slurp 2>/dev/null </dev/null | jq -e --arg h "$3" \
    --arg l "$(printf '%s' "$HUMAN_REVIEWERS" | tr ', ' '\n\n')" '($l|ascii_downcase|split("\n")) as $ok
    | [add // [] | .[] | select(.state=="APPROVED" or .state=="CHANGES_REQUESTED")]
    | reduce .[] as $r ({}; .[$r.user.login|ascii_downcase] = $r) | to_entries
    | any(.[]; .value.state=="APPROVED" and .value.commit_id==$h and (.key as $u | any($ok[]; . != "" and . == $u)))' >/dev/null 2>&1
}
label=0; notify=0; repos=()
for a in "$@"; do case "$a" in --label) label=1;; --notify) notify=1;; *) repos+=("$a");; esac; done
[ -n "${GH_ACCOUNT:-}" ] && { GH_TOKEN=$(gh auth token -u "$GH_ACCOUNT") || exit 1; export GH_TOKEN; }
if [ ${#repos[@]} -eq 0 ]; then
  while read -r r; do repos+=("$r"); done < <(grep -v '^#' "$ST/queue.txt" 2>/dev/null | awk 'NF{print $1}' | sort -u)
fi
[ ${#repos[@]} -gt 0 ] || { echo "human-queue: no repos given and no queue file"; exit 0; }
n=0
for R in "${repos[@]}"; do
  for P in $(gh pr list -R "$R" --state open --limit 100 --json number --jq '.[].number'); do
    H=$(gh pr view "$P" -R "$R" --json headRefOid --jq .headRefOid)
    j=$($RT --pr "$R" "$P" 2>/dev/null); t=$(jq -r '.tier // "human"' <<<"$j" 2>/dev/null || echo human)
    if jq -e '.policy_found == false' >/dev/null 2>&1 <<<"$j"; then continue; fi   # repo has no policy
    approved=0; human_approved "$R" "$P" "$H" && approved=1
    if [ "$t" = human ] && [ $approved = 0 ]; then
      n=$((n + 1))
      title=$(gh pr view "$P" -R "$R" --json title --jq .title)
      echo "== NEEDS YOU: $R#$P  $title"
      echo "   head $H"
      jq -r '.reasons[] | "   - " + .' <<<"$j"
      echo "   read:    gh pr diff $P -R $R -- $(jq -r '.human_files|join(" ")' <<<"$j")"
      echo "   approve: ! $HERE/human-approve.sh $R $P $H"
      [ $label = 1 ] && gh pr edit "$P" -R "$R" --add-label needs-human-review >/dev/null 2>&1
    elif [ $label = 1 ]; then
      gh pr edit "$P" -R "$R" --remove-label needs-human-review >/dev/null 2>&1
    fi
  done
done
echo "human-queue: $n PR(s) waiting on your review"
if [ $notify = 1 ] && [ $n -gt 0 ]; then
  msg="$n PR(s) need your review"
  if command -v osascript >/dev/null 2>&1; then osascript -e "display notification \"$msg\" with title \"Human review queue\"" >/dev/null 2>&1
  elif command -v notify-send >/dev/null 2>&1; then notify-send "Human review queue" "$msg" >/dev/null 2>&1   # Linux
  else echo "human-queue: $msg (no osascript or notify-send to notify with)" >&2; fi
fi
exit 0
