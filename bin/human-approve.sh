#!/bin/bash
# human-approve.sh OWNER/REPO PR SHA [note]: record YOUR review of a human-tier PR at one exact sha.
# Run it yourself with a leading `!` in a Claude pane (or in a plain terminal). Sessions are blocked from running
# it or writing its file (lane-guard). A new commit on the PR needs a new approval: the record is per sha.
# The record counts only in solo mode (HUMAN_REVIEWERS empty) or with ALLOW_LOCAL_APPROVALS=1. With HUMAN_REVIEWERS
# set, merge-queue.sh and human-queue.sh need an APPROVED GitHub review at the exact head sha by one of those logins.
set -euo pipefail
[ $# -ge 3 ] || { sed -n '2,4p' "$0"; exit 2; }
R=$1; P=$2; SHA=$3; NOTE=${4:-}
[ ${#SHA} -eq 40 ] || { echo "human-approve: give the FULL 40-char sha (got ${#SHA})" >&2; exit 2; }
ST=${MERGE_STATE:-$HOME/.local/state/merge-queue}; mkdir -p "$ST"
printf '%s %s %s %s %s\n' "$R" "$P" "$SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NOTE" >> "$ST/human-approved.txt"
if [ -n "${HUMAN_REVIEWERS:-}" ] && [ "${ALLOW_LOCAL_APPROVALS:-0}" != 1 ]; then
  echo "Recorded $R#$P at ${SHA:0:12}, but HUMAN_REVIEWERS is set: the queue needs your APPROVED GitHub review at that sha."
else
  echo "Recorded: you reviewed $R#$P at ${SHA:0:12}. The merge queue may now merge it at that sha."
fi
