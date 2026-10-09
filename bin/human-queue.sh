#!/bin/bash
# human-queue.sh [--label] [--notify] [OWNER/REPO ...]: what is waiting on YOUR review, and exactly which files.
# For each open PR in the repos given (default: the repos in $MERGE_STATE/queue.txt), it runs review_tier.py and
# lists the human-tier PRs not yet approved at their current head, with the reasons and the files to read.
#   --label   add the `needs-human-review` label to those PRs (and remove it once approved)
#   --notify  one macOS notification with the count
# Read-only on GitHub unless --label. Agents run it to flag; you run it to see your queue.
HERE=$(cd "$(dirname "$0")" && pwd)
ST=${MERGE_STATE:-$HOME/.local/state/merge-queue}
RT=${REVIEW_TIER_CMD:-python3 $HERE/review_tier.py}
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
    approved=0; grep -q "^$R $P $H " "$ST/human-approved.txt" 2>/dev/null && approved=1
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
[ $notify = 1 ] && [ $n -gt 0 ] && osascript -e "display notification \"$n PR(s) need your review\" with title \"Human review queue\"" >/dev/null 2>&1
exit 0
