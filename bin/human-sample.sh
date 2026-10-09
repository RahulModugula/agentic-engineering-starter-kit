#!/bin/bash
# human-sample.sh [N] [DAYS] OWNER/REPO...: pick N random AGENT-tier PRs merged in the last DAYS (default 5, 7) for a
# human spot-check, so mistakes the AI verifier lets through still reach a person. Read-only.
HERE=$(cd "$(dirname "$0")" && pwd)
N=${1:-5}; D=${2:-7}; shift 2 2>/dev/null || shift $#
[ $# -gt 0 ] || { sed -n '2,3p' "$0"; exit 2; }
RT=${REVIEW_TIER_CMD:-python3 $HERE/review_tier.py}
since=$(python3 -c "import datetime as d,sys;print((d.datetime.now(d.timezone.utc)-d.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%d'))" "$D")
for R in "$@"; do
  gh pr list -R "$R" --state merged --search "merged:>=$since" --limit 200 --json number --jq '.[].number' \
  | while read -r P; do $RT --pr "$R" "$P" </dev/null >/dev/null 2>&1 && echo "$R $P"; done   # stdin = the PR list
done | awk 'BEGIN{srand()} {print rand() "\t" $0}' | sort -n | cut -f2- | head -n "$N" \
  | while read -r R P; do echo "spot-check: gh pr view $P -R $R --web    (agent-tier, merged in the last $D days)"; done
