#!/bin/bash
# merge-guard / merge-queue against a fake gh: must merge only the right PRs at the right shas, and refuse the rest.
. "$(dirname "$0")/lib.sh"
mkdir -p "$TMP/bin" "$TMP/gh" "$TMP/state"
cp "$ROOT/tests/fixtures/fake-gh" "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_GH="$TMP/gh" POLL_TRIES=1 POLL_SLEEP=0 POLL_RECHECK=0 MQ_HERE="$ROOT/bin" MERGE_STATE="$TMP/state"
unset HUMAN_REVIEWERS ALLOW_LOCAL_APPROVALS VERIFIER_LOGIN VERIFY_FROM CI_WORKFLOWS URGENT DRY_RUN MERGE_MODE REQUIRE_VERIFIED REVIEW_TIERS GH_ACCOUNT
SHA=1234567890abcdef1234567890abcdef12345678
# Tier stub: $TMP/tier holds "none" (no policy), "agent" or "human"; "error" makes it fail.
echo none > "$TMP/tier"
cat > "$TMP/bin/tierstub" <<EOF
#!/bin/bash
[ -n "\${TIER_EAT_STDIN:-}" ] && cat >/dev/null
case \$(cat $TMP/tier) in
  none)  echo '{"tier":"human","policy_found":false,"reasons":["no .review-tiers on the base branch: every path defaults to human"],"human_files":[]}'; exit 10;;
  agent) echo '{"tier":"agent","policy_found":true,"reasons":[],"human_files":[]}'; exit 0;;
  human) echo '{"tier":"human","policy_found":true,"reasons":["src/auth/x.py: matches a human rule"],"human_files":["src/auth/x.py"]}'; exit 10;;
  spoof) echo '{"tier":"human","policy_found":true,"reasons":["no .review-tiers x: matches a human rule"],"human_files":["no .review-tiers x"]}'; exit 10;;
  *) exit 2;;
esac
EOF
chmod +x "$TMP/bin/tierstub"; export REVIEW_TIER_CMD="$TMP/bin/tierstub"
pr() {  # pr REPO NUM STATE MERGESTATE CHECKS(ok,pending,fail counts) [comment]
  local ok=$5 pe=$6 fa=$7 c=${8:-}
  jq -n --arg s "$3" --arg m "$4" --arg h "$SHA" --argjson ok "$ok" --argjson pe "$pe" --argjson fa "$fa" --arg c "$c" '{
    state:$s, headRefOid:$h, mergeable:"MERGEABLE", mergeStateStatus:$m,
    statusCheckRollup: ([range($ok)|{status:"COMPLETED",conclusion:"SUCCESS"}] + [range($pe)|{status:"IN_PROGRESS"}] + [range($fa)|{status:"COMPLETED",conclusion:"FAILURE"}]),
    comments: (if $c=="" then [] else [{body:$c}] end)}' > "$FAKE_GH/$(echo "$1" | tr / _)-$2.json"
}
G="$ROOT/bin/merge-guard.sh"
# merge-guard
pr o/r 1 OPEN CLEAN 3 0 0;  rc 0 "guard merges a green PR at its sha" /bin/bash "$G" o/r 1 "$SHA" 3
pr o/r 2 OPEN CLEAN 3 0 0;  rc 1 "guard refuses a different (full, well-formed) sha" /bin/bash "$G" o/r 2 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 3
pr o/r 3 OPEN CLEAN 2 1 0;  rc 1 "guard refuses pending checks" /bin/bash "$G" o/r 3 "$SHA" 3
pr o/r 4 OPEN CLEAN 2 0 1;  rc 1 "guard refuses a failed check" /bin/bash "$G" o/r 4 "$SHA" 3
pr o/r 5 OPEN DIRTY 3 0 0;  rc 1 "guard refuses a conflicted PR" /bin/bash "$G" o/r 5 "$SHA" 3
pr o/r 6 OPEN CLEAN 2 0 0;  rc 1 "guard refuses too few checks" /bin/bash "$G" o/r 6 "$SHA" 3
pr o/r 7 OPEN CLEAN 3 0 0;  rc 1 "guard refuses a too-short sha prefix" /bin/bash "$G" o/r 7 123 3
pr o/r 8 OPEN UNSTABLE 3 0 0; rc 1 "guard refuses UNSTABLE (a non-required check failed)" /bin/bash "$G" o/r 8 "$SHA" 3
pr o/r 9 OPEN DRAFT 3 0 0;  rc 1 "guard refuses a draft" /bin/bash "$G" o/r 9 "$SHA" 3
pr o/r 11 OPEN CLEAN 3 0 0
jq '.statusCheckRollup += [{"state":"EXPECTED"}]' "$FAKE_GH/o_r-11.json" > "$TMP/x" && mv "$TMP/x" "$FAKE_GH/o_r-11.json"
rc 1 "guard waits on (does not merge past) an EXPECTED required status" /bin/bash "$G" o/r 11 "$SHA" 3
rc 2 "guard usage error" /bin/bash "$G" o/r
eq "only PR 1 was merged" "$(cat "$FAKE_GH/merged.log")" "o/r 1"
# mergeStateStatus is an allow-list: CLEAN or HAS_HOOKS merge; empty, unknown or new states refuse.
: > "$FAKE_GH/merged.log"
pr o/r 31 OPEN HAS_HOOKS 3 0 0;  rc 0 "guard merges HAS_HOOKS (allow-listed)" /bin/bash "$G" o/r 31 "$SHA" 3
pr o/r 32 OPEN "" 3 0 0;         rc 1 "guard refuses an empty mergeStateStatus" /bin/bash "$G" o/r 32 "$SHA" 3
pr o/r 33 OPEN NEW_STATE 3 0 0;  out=$(/bin/bash "$G" o/r 33 "$SHA" 3 2>&1); r=$?
eq "guard refuses a mergeStateStatus it doesn't know" "$r" "1"
ok "refusal names the allow-list" grep -q "mergeStateStatus='NEW_STATE' (merges only on CLEAN or HAS_HOOKS)" <<<"$out"
eq "only the HAS_HOOKS PR was merged" "$(cat "$FAKE_GH/merged.log")" "o/r 31"

# merge-queue (window mode, verified gate)
: > "$FAKE_GH/merged.log"
pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"
pr o/q 11 OPEN CLEAN 3 0 0 "VERIFIED $SHA"          # comment but no coordinator record -> skip
pr o/q 12 OPEN CLEAN 3 0 0                          # no VERIFIED comment -> skip
pr o/q 13 MERGED CLEAN 3 0 0 "VERIFIED $SHA"        # already merged -> skip
printf 'o/q 10 %s\no/q 11 %s\no/q 12 %s\n# o/q 14 %s\no/q 13 %s\n' $SHA $SHA $SHA $SHA $SHA > "$TMP/state/queue.txt"
printf 'o/q 10 %s\n' $SHA > "$TMP/state/verified.txt"
out=$(/bin/bash "$ROOT/bin/merge-queue.sh" 2>&1)
eq "queue merged only the verified PR" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
ok "queue explains the unrecorded PR" grep -q "11 has a VERIFIED comment but no coordinator record" <<<"$out"
ok "queue explains the unverified PR" grep -q "12 awaiting" <<<"$out"

# window: a merge 10 minutes ago holds the repo; URGENT=1 overrides
: > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"
export FAKE_LAST_MERGE=$(python3 -c "import datetime as d;print((d.datetime.now(d.timezone.utc)-d.timedelta(minutes=10)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
out=$(/bin/bash "$ROOT/bin/merge-queue.sh" 2>&1)
ok "window holds a repo merged 10 min ago" grep -q "window closed" <<<"$out"
eq "nothing merged inside the window" "$(cat "$FAKE_GH/merged.log")" ""
URGENT=1 /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1
eq "URGENT=1 merges inside the window" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
unset FAKE_LAST_MERGE

# DRY_RUN merges nothing
: > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"
DRY_RUN=1 /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1
eq "DRY_RUN merges nothing" "$(cat "$FAKE_GH/merged.log")" ""

# green mode (change 5, off by default): held while main is red or a deploy runs; stops after a red batch
echo "completed failure" > "$FAKE_GH/main-ci"
out=$(MERGE_MODE=green /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1)
ok "green mode holds a repo whose main is red" grep -q "not green; held" <<<"$out"
eq "nothing merged onto red main" "$(cat "$FAKE_GH/merged.log")" ""
echo "completed success" > "$FAKE_GH/main-ci"
printf '#!/bin/bash\nexit 0\n' > "$TMP/state/deploy-busy.sh"; chmod +x "$TMP/state/deploy-busy.sh"
out=$(MERGE_MODE=green /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1)
ok "green mode holds while a deploy runs" grep -q "deploy running; held" <<<"$out"
rm "$TMP/state/deploy-busy.sh"
MERGE_MODE=green MAIN_CI_SLEEP=0 /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1; r=$?
eq "green mode merges when main is green and idle" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
eq "green mode exits 0 when main stays green" "$r" "0"
ok "green mode reads only the CI workflow's push runs" grep -q -- "--workflow ci.yml --event push" "$FAKE_GH/run-list.log"
ok "after a batch it pins the NEW main head" grep -q -- "--commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$FAKE_GH/run-list.log"
: > "$FAKE_GH/run-list.log"; : > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"
CI_WORKFLOWS="o/q=test.yml" MERGE_MODE=green MAIN_CI_SLEEP=0 /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1
ok "per-repo CI workflow is honoured" grep -q -- "--workflow test.yml" "$FAKE_GH/run-list.log"
# after-batch red: simulate main going red after the merge
: > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"
printf '#!/bin/bash\necho "completed failure" > "$FAKE_GH/main-ci"\n' > "$TMP/state/post-merge.sh"; chmod +x "$TMP/state/post-merge.sh"
out=$(MERGE_MODE=green MAIN_CI_SLEEP=0 /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1); r=$?
eq "green mode exits 1 when main turns red after a batch" "$r" "1"
ok "green mode says why it stopped" grep -q "main CI is 'completed failure' after this batch" <<<"$out"
# A run that hasn't started yet for the new sha ("null null") is not success: it keeps waiting, then stops.
: > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"; echo "completed success" > "$FAKE_GH/main-ci"
printf '#!/bin/bash\necho "null null" > "$FAKE_GH/main-ci"\n' > "$TMP/state/post-merge.sh"
out=$(MERGE_MODE=green MAIN_CI_SLEEP=0 MAIN_CI_TRIES=2 /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1); r=$?
eq "no CI run yet for the new head: not treated as green" "$r" "1"
ok "says CI did not finish" grep -q "did not finish" <<<"$out"

rc 1 "queue refuses without a queue file" env MERGE_STATE="$TMP/empty" /bin/bash "$ROOT/bin/merge-queue.sh"
# Review findings: exact 40-char sha only; malformed queue lines are skipped, never merged unverified.
pr o/r 21 OPEN CLEAN 3 0 0;  rc 1 "guard refuses a 7-char prefix of the right sha" /bin/bash "$G" o/r 21 "${SHA:0:7}" 3
rc 1 "guard refuses a non-numeric PR" /bin/bash "$G" o/r '#21' "$SHA" 3
pr o/r 22 OPEN CLEAN 0 0 0;  rc 1 "guard refuses a non-numeric minimum-checks (zero checks can't pass)" /bin/bash "$G" o/r 22 "$SHA" abc
rc 1 "guard refuses minimum-checks 0" /bin/bash "$G" o/r 22 "$SHA" 0
: > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"
printf 'o/q #10 %s\no/q 10 %s\n' "$SHA" "${SHA:0:12}" > "$TMP/state/queue.txt"
out=$(echo agent > "$TMP/tier"; /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1)
eq "malformed queue lines merge nothing" "$(cat "$FAKE_GH/merged.log")" ""
ok "malformed lines are reported" grep -q "SKIP malformed queue line" <<<"$out"
printf 'o/q 10 %s\n' "$SHA" > "$TMP/state/queue.txt"

# VERIFY_FROM must be owner/repo=N: a garbage N used to make `-gt` error, skipping the VERIFIED check.
rm -f "$TMP/state/post-merge.sh"; echo agent > "$TMP/tier"
: > "$FAKE_GH/merged.log"; pr o/q 12 OPEN CLEAN 3 0 0; printf 'o/q 12 %s\n' "$SHA" > "$TMP/state/queue.txt"
out=$(VERIFY_FROM="o/q=abc" /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1); r=$?
eq "VERIFY_FROM with a non-number stops the queue" "$r" "1"
eq "VERIFY_FROM garbage merges nothing unverified" "$(cat "$FAKE_GH/merged.log")" ""
ok "says which VERIFY_FROM entry is bad" grep -q "bad VERIFY_FROM entry 'o/q=abc'" <<<"$out"
rc 1 "VERIFY_FROM with an empty number stops" env VERIFY_FROM="o/q=" /bin/bash "$ROOT/bin/merge-queue.sh"
rc 1 "VERIFY_FROM '*' stops" env VERIFY_FROM="*" /bin/bash "$ROOT/bin/merge-queue.sh"
VERIFY_FROM="x/y=1 o/q=12" /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1
eq "a valid VERIFY_FROM still grandfathers PRs at or below N" "$(cat "$FAKE_GH/merged.log")" "o/q 12"
# The queue is read on fd 3: a gh that drains stdin must not swallow the remaining queue lines.
: > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"; pr o/q 15 OPEN CLEAN 3 0 0 "VERIFIED $SHA"
printf 'o/q 10 %s\no/q 15 %s\n' "$SHA" "$SHA" > "$TMP/state/queue.txt"; printf 'o/q 10 %s\no/q 15 %s\n' "$SHA" "$SHA" > "$TMP/state/verified.txt"
FAKE_GH_EAT_STDIN=1 /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1 </dev/null
eq "a stdin-reading gh doesn't eat queue lines" "$(cat "$FAKE_GH/merged.log")" "$(printf 'o/q 10\no/q 15')"
printf 'o/q 10 %s\n' "$SHA" > "$TMP/state/queue.txt"; printf 'o/q 10 %s\n' "$SHA" > "$TMP/state/verified.txt"
# The private copy is removed on exit, on success and on a STOP.
mkdir -p "$TMP/qtmp"; : > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"
TMPDIR="$TMP/qtmp" /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1
TMPDIR="$TMP/qtmp" MERGE_STATE="$TMP/empty" /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1
eq "the queue ran from its copy" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
eq "no temp copy left behind" "$(ls "$TMP/qtmp")" ""
# VERIFIER_LOGIN: only that login's VERIFIED comment counts (case-insensitive, as GitHub logins are).
: > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0
jq --arg b "VERIFIED $SHA" '.comments=[{author:{login:"lane-bot"},body:$b}]' "$FAKE_GH/o_q-10.json" > "$TMP/x" && mv "$TMP/x" "$FAKE_GH/o_q-10.json"
out=$(VERIFIER_LOGIN=verifier-bot /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1)
eq "VERIFIER_LOGIN: a VERIFIED comment by another login doesn't count" "$(cat "$FAKE_GH/merged.log")" ""
ok "says whose VERIFIED comment it waits for" grep -q "awaiting 'VERIFIED $SHA' comment from verifier-bot" <<<"$out"
jq --arg b "VERIFIED $SHA" '.comments+=[{author:{login:"Verifier-Bot"},body:$b}]' "$FAKE_GH/o_q-10.json" > "$TMP/x" && mv "$TMP/x" "$FAKE_GH/o_q-10.json"
VERIFIER_LOGIN=verifier-bot /bin/bash "$ROOT/bin/merge-queue.sh" >/dev/null 2>&1
eq "VERIFIER_LOGIN: the verifier's own comment merges" "$(cat "$FAKE_GH/merged.log")" "o/q 10"

# Human-review tier
rm -f "$TMP/state/post-merge.sh"; echo "completed success" > "$FAKE_GH/main-ci"
qrun() { : > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"; /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1; }
echo agent > "$TMP/tier"; qrun >/dev/null
eq "agent tier merges on VERIFIED alone" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
echo human > "$TMP/tier"; out=$(qrun)
eq "human tier does NOT merge without a person" "$(cat "$FAKE_GH/merged.log")" ""
ok "human tier names the files to read" grep -q "NEEDS HUMAN REVIEW (core code): src/auth/x.py" <<<"$out"
ok "human tier prints the approve command" grep -q "human-approve.sh o/q 10 $SHA" <<<"$out"
echo error > "$TMP/tier"; qrun >/dev/null
eq "tier check error fails closed (no merge)" "$(cat "$FAKE_GH/merged.log")" ""
echo human > "$TMP/tier"
echo "o/q 10 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2026-10-09T00:00:00Z" > "$TMP/state/human-approved.txt"
qrun >/dev/null
eq "an approval for an OLDER sha doesn't count" "$(cat "$FAKE_GH/merged.log")" ""
MERGE_STATE=$TMP/state /bin/bash "$ROOT/bin/human-approve.sh" o/q 10 "$SHA" "read auth" >/dev/null
qrun >/dev/null
eq "approval at the exact sha merges" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
rc 2 "human-approve refuses a short sha" env MERGE_STATE=$TMP/state /bin/bash "$ROOT/bin/human-approve.sh" o/q 10 abc
rm "$TMP/state/human-approved.txt"
# With HUMAN_REVIEWERS set, a GitHub review (REST: user.login, commit_id) counts only from a listed login, at the
# head commit, and only if that login's latest decision is APPROVED. The fake splits reviews over two pages.
add_review() {  # add_review [LOGIN STATE COMMIT]... (oldest first)
  local r='[]'
  while [ $# -ge 3 ]; do r=$(jq -c --arg w "$1" --arg s "$2" --arg c "$3" '. + [{state:$s,user:{login:$w},commit_id:$c}]' <<<"$r"); shift 3; done
  jq --argjson r "$r" '.api_reviews=$r' "$FAKE_GH/o_q-10.json" > "$TMP/x" && mv "$TMP/x" "$FAKE_GH/o_q-10.json"
}
hq() { : > "$FAKE_GH/merged.log"; pr o/q 10 OPEN CLEAN 3 0 0 "VERIFIED $SHA"; add_review "$@"; /bin/bash "$ROOT/bin/merge-queue.sh" 2>&1; }
OLD=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
export HUMAN_REVIEWERS="bob, alice"
hq agent-bot APPROVED "$SHA" >/dev/null
eq "approval by a non-listed login doesn't count" "$(cat "$FAKE_GH/merged.log")" ""
hq alice APPROVED "$OLD" >/dev/null
eq "a listed login's approval at an OLDER commit doesn't count" "$(cat "$FAKE_GH/merged.log")" ""
hq alice APPROVED "$SHA" alice CHANGES_REQUESTED "$SHA" >/dev/null
eq "an approval later replaced by changes-requested doesn't count" "$(cat "$FAKE_GH/merged.log")" ""
hq agent-bot COMMENTED "$SHA" Alice APPROVED "$SHA" >/dev/null
eq "approval by a listed human at head merges (second page, any case)" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
out=$(MERGE_STATE=$TMP/state /bin/bash "$ROOT/bin/human-approve.sh" o/q 10 "$SHA" "read auth")
ok "human-approve warns its record won't count under HUMAN_REVIEWERS" grep -q "needs your APPROVED GitHub review" <<<"$out"
out=$(hq)
eq "a local record does NOT count when HUMAN_REVIEWERS is set" "$(cat "$FAKE_GH/merged.log")" ""
ok "says which GitHub review it needs" grep -q "needs an APPROVED GitHub review at $SHA by one of: bob, alice" <<<"$out"
export ALLOW_LOCAL_APPROVALS=1; hq >/dev/null; unset ALLOW_LOCAL_APPROVALS
eq "ALLOW_LOCAL_APPROVALS=1 lets the local record count" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
# human-queue applies the same rule, so a PR the queue won't merge still shows as waiting.
pr o/q 10 OPEN CLEAN 3 0 0; export FAKE_OPEN_PRS=10
out=$(/bin/bash "$ROOT/bin/human-queue.sh" o/q 2>&1)
ok "human-queue lists a local-only approval as waiting under HUMAN_REVIEWERS" grep -q "1 PR(s) waiting" <<<"$out"
add_review agent-bot APPROVED "$SHA"; out=$(/bin/bash "$ROOT/bin/human-queue.sh" o/q 2>&1)
ok "human-queue ignores an approval by a non-listed login" grep -q "1 PR(s) waiting" <<<"$out"
add_review alice APPROVED "$SHA"; out=$(/bin/bash "$ROOT/bin/human-queue.sh" o/q 2>&1)
ok "human-queue counts a listed GitHub approval at head" grep -q "0 PR(s) waiting" <<<"$out"
unset HUMAN_REVIEWERS; add_review
out=$(/bin/bash "$ROOT/bin/human-queue.sh" o/q 2>&1)
ok "human-queue: solo mode counts the local record" grep -q "0 PR(s) waiting" <<<"$out"
rm "$TMP/state/human-approved.txt"
# --notify: osascript (macOS), else notify-send, else stderr. PATH holds only what the script needs.
NB="$TMP/nbin"; mkdir -p "$NB"
for b in bash dirname grep awk sort jq cat sed tr mktemp mv; do ln -sf "$(type -P $b)" "$NB/$b"; done
ln -sf "$TMP/bin/gh" "$NB/gh"
nq() { PATH="$NB" /bin/bash "$ROOT/bin/human-queue.sh" --notify o/q 2>&1 >/dev/null; }
eq "notify with neither tool: one line on stderr" "$(nq)" "human-queue: 1 PR(s) need your review (no osascript or notify-send to notify with)"
printf '#!/bin/bash\necho "notify-send $*" >> %s/notify.log\n' "$TMP" > "$NB/notify-send"; chmod +x "$NB/notify-send"
nq >/dev/null; eq "notify falls back to notify-send without osascript" "$(cat "$TMP/notify.log")" "notify-send Human review queue 1 PR(s) need your review"
printf '#!/bin/bash\necho "osascript $*" >> %s/notify.log\n' "$TMP" > "$NB/osascript"; chmod +x "$NB/osascript"
: > "$TMP/notify.log"; nq >/dev/null
ok "notify prefers osascript when present (macOS)" grep -q '^osascript -e display notification "1 PR(s) need your review"' "$TMP/notify.log"
eq "and only osascript" "$(wc -l < "$TMP/notify.log" | tr -d ' ')" "1"
unset FAKE_OPEN_PRS
# human-sample: the tier check must not eat the PR list it is reading.
echo agent > "$TMP/tier"; export FAKE_MERGED_PRS="1 2 3"
n=$(TIER_EAT_STDIN=1 /bin/bash "$ROOT/bin/human-sample.sh" 5 7 o/s </dev/null | grep -c "spot-check")
eq "human-sample sees every merged PR even if the tier check reads stdin" "$n" "3"
unset FAKE_MERGED_PRS; echo human > "$TMP/tier"
echo none > "$TMP/tier"; qrun >/dev/null
eq "repo without a policy file: tiering off (today's behaviour)" "$(cat "$FAKE_GH/merged.log")" "o/q 10"
# Review finding: a file NAMED like the no-policy reason must not switch the gate off.
echo spoof > "$TMP/tier"; qrun >/dev/null
eq "a file named 'no .review-tiers…' does not bypass human review" "$(cat "$FAKE_GH/merged.log")" ""
finish
