#!/bin/bash
# review_tier.py: core backend is flagged human; UI/tests/bench may be agent-only; every dodge is caught.
. "$(dirname "$0")/lib.sh"
RT="python3 $ROOT/bin/review_tier.py"
R=$TMP/repo; mkdir -p "$R"; cd "$R" || exit 1
git init -q -b main; git config user.email t@example.test; git config user.name t
mkdir -p src/auth src/api web/components tests bench docs
cat > .review-tiers <<'EOF'
default human
agent web/**
agent tests/**
agent bench/**
agent docs/**
human src/auth/**
escalate (import|from)\s+.*\b(db|database|auth|iam|secrets?)\b
EOF
echo "def login(): pass" > src/auth/login.py
echo "def handler(): pass" > src/api/h.py
echo "<div/>" > web/components/A.tsx
printf 'def test_a():\n    assert 1\n    assert 2\n' > tests/test_a.py
echo "x" > bench/b.py
git add -A; git commit -qm base; git branch base
tier() { $RT --local --base base --head HEAD | jq -r .tier; }
change() { git checkout -q -B work base; "$@"; git add -A; git commit -qm c --allow-empty; }

change sh -c 'echo "<span/>" >> web/components/A.tsx'
eq "UI-only change: agent" "$(tier)" "agent"
change sh -c 'printf "    assert 3\n" >> tests/test_a.py; echo y >> bench/b.py; echo d > docs/x.md'
eq "tests + bench + docs: agent" "$(tier)" "agent"
change sh -c 'echo "# tweak" >> src/auth/login.py'
eq "auth change: human" "$(tier)" "human"
change sh -c 'echo "# tweak" >> src/api/h.py'
eq "unlisted backend path: human (default)" "$(tier)" "human"
change sh -c 'git mv src/auth/login.py web/components/login.py'
eq "moving core code into an agent path: human" "$(tier)" "human"
change sh -c 'git rm -q tests/test_a.py'
eq "deleting a test file: human" "$(tier)" "human"
change sh -c 'printf "def test_a():\n    assert 1\n" > tests/test_a.py'
eq "removing assertions: human" "$(tier)" "human"
change sh -c 'echo "agent src/**" >> .review-tiers'
eq "loosening the policy file: human" "$(tier)" "human"
# The policy is read from BASE: a PR that loosens it AND touches auth is still human.
change sh -c 'echo "agent src/**" >> .review-tiers; echo "# x" >> src/auth/login.py'
ok "policy comes from the base branch" grep -q "src/auth/login.py: matches a human rule" <<<"$($RT --local --base base --head HEAD)"
# No policy file at all: everything human.
git checkout -q -B nopol base; git rm -q .review-tiers; git commit -qm rm; git branch -f base2 HEAD
git checkout -q -B w2 base2; echo "<b/>" >> web/components/A.tsx; git commit -qam w
eq "no policy on base: human" "$($RT --local --base base2 --head HEAD | jq -r .tier)" "human"
# Escalation: an agent-tier file that starts importing core code
change sh -c 'echo "import { getUser } from \"../../src/auth\";" >> web/components/A.tsx'
eq "UI file importing auth code: human (escalate)" "$(tier)" "human"
change sh -c 'echo "from app.db import session" >> bench/b.py'
eq "bench file importing the database: human (escalate)" "$(tier)" "human"
change sh -c 'echo "// uses the authorization header from context" >> web/components/A.tsx'
eq "a mere word 'authorization' in UI: still agent" "$(tier)" "agent"
# Skipped tests
change sh -c 'printf "@pytest.mark.skip\ndef test_b():\n    assert 3\n" >> tests/test_a.py'
eq "newly skipped test: human" "$(tier)" "human"
change sh -c 'echo "it.only(\"x\", () => { expect(1).toBe(1) })" > tests/a.test.js'
eq "it.only (silently skips the rest): human" "$(tier)" "human"
# Red-to-green shortcuts are human, whatever the path
mkdir -p tests/__snapshots__; echo "<b/>" > tests/__snapshots__/a.snap; git add -A; git commit -qm snap; git branch -f base HEAD
change sh -c 'echo "<i/>" > tests/__snapshots__/a.snap'
eq "rewritten snapshot: human" "$(tier)" "human"
change sh -c 'echo "<div/> {/* istanbul ignore next */}" >> web/components/A.tsx'
eq "coverage exclusion in UI: human" "$(tier)" "human"
change sh -c 'printf "@pytest.mark.flaky(reruns=3)\ndef test_c():\n    assert 1\n" >> tests/test_a.py'
eq "flaky marker on a test: human" "$(tier)" "human"
change sh -c 'echo "x = 1  # pragma: no mutate" >> bench/b.py'
eq "mutation exclusion: human" "$(tier)" "human"
# Review findings (2026-10-09): a can't-fail assert swap; a bare-directory rule; a non-ASCII path.
change sh -c 'printf "def test_a():\n    assert True\n    assert 2\n" > tests/test_a.py'
eq "assert x replaced by 'assert True': human" "$(tier)" "human"
out=$(python3 -c "
import sys; sys.path.insert(0, '$ROOT/bin'); import review_tier as r
print(r.decide([{'path':'src/auth/login.py','status':'M','patch':'+x'}], 'default agent\nhuman src/auth\n')['tier'])")
eq "bare-directory rule 'human src/auth' covers files under it" "$out" "human"
mkdir -p "web/ünï"; echo x > "web/ünï/k.tsx"; git add -A; git commit -qm u; git branch -f base HEAD
change sh -c 'echo y >> "web/ünï/k.tsx"'
eq "non-ASCII path in an agent dir is read correctly (agent, not quoted-path default)" "$(tier)" "agent"
# Second review: a test renamed out of the tests is a deletion; an EMPTY policy is still a policy.
change sh -c 'git mv tests/test_a.py tests/disabled_a.txt'
eq "test renamed to a non-test file: human" "$(tier)" "human"
# Third review: only real runner patterns count as runnable. A .py in tests/ that pytest won't collect is not a test,
# so renaming test_a.py to it is a disguised deletion.
change sh -c 'git mv tests/test_a.py tests/helper_a.py'
eq "test renamed to a non-collected tests/helper_a.py: human" "$(tier)" "human"
out=$(python3 -c "
import sys; sys.path.insert(0, '$ROOT/bin'); import review_tier as r
yes = ['test_x.py', 'pkg/test_x.py', 'x_test.py', 'a/x_test.go', 'a.test.js', 'a.test.jsx', 'b/a.test.ts', 'a.test.tsx',
       'a.spec.js', 'a.spec.jsx', 'a.spec.ts', 'c/a.spec.tsx', '__tests__/a.js', 'src/__tests__/util/b.ts', 'tests/test_x.sh']
no = ['latest.py', 'contest.md', 'testing/guide.md', 'tests/helper.py', 'tests/conftest.py', 'src/attest.go', 'tests/x.sh',
      'test.py', 'scripts/test_x.sh', '_test.py', 'a.test.md', 'protest_x.py']
print(' '.join([p for p in yes if not r.RUNNABLE_TEST.search(p)] + [p for p in no if r.RUNNABLE_TEST.search(p)]) or 'none')")
eq "RUNNABLE_TEST matches exactly the runner patterns (listed: wrong ones)" "$out" "none"
# Policies shipped with the kit: files that change how tests run / how agents behave / what 'tested' means are human.
pol_tier() { python3 -c "
import sys; sys.path.insert(0, '$ROOT/bin'); import review_tier as r
rules, d, _ = r.parse_policy(open(sys.argv[1]).read())
print(' '.join(r.classify_path(p, rules, d)[0] for p in sys.argv[2:]))" "$@"; }
eq "generic policy: conftest.py (any depth), .claude/**, CLAUDE.md (any depth) are human" \
  "$(pol_tier "$ROOT/examples/review-tiers/generic.review-tiers" conftest.py tests/conftest.py a/b/conftest.py \
     .claude/settings.json .claude/hooks/x.sh CLAUDE.md docs/CLAUDE.md tests/test_a.py docs/x.md)" \
  "human human human human human human human agent agent"
eq "this repo's policy: mutants.txt, mutate.py, fixtures/** are human; other tests agent" \
  "$(pol_tier "$ROOT/.review-tiers" tests/mutants.txt tests/mutate.py tests/fixtures/a.json tests/fixtures/d/e.txt tests/test_scan.sh)" \
  "human human human human agent"
git checkout -q -B emptypol base; : > .review-tiers; git commit -qam "empty policy"; git branch -f base3 HEAD
git checkout -q -B w3 base3; echo "<u/>" >> web/components/A.tsx; git commit -qam w
eq "empty policy file: policy_found is true (tiering stays on)" "$($RT --local --base base3 --head HEAD | jq -r .policy_found)" "true"
eq "empty policy file: everything defaults to human" "$($RT --local --base base3 --head HEAD | jq -r .tier)" "human"
# Unit check of the patch-missing rule (GitHub omits patch for huge diffs): fail closed
out=$(python3 -c "
import sys; sys.path.insert(0, '$ROOT/bin'); import review_tier as r
print(r.decide([{'path':'tests/t.py','status':'M','patch':None}], open('.review-tiers').read())['tier'])")
eq "agent-tier test file with no patch available: human" "$out" "human"
# Exit codes: 0 agent, 10 human, 2 error (fail closed)
change sh -c 'echo "<i/>" >> web/components/A.tsx'
rc 0 "exit 0 for agent" $RT --local --base base --head HEAD
change sh -c 'echo "# t" >> src/auth/login.py'
rc 10 "exit 10 for human" $RT --local --base base --head HEAD
rc 2 "exit 2 (human) when the diff can't be read" $RT --local --base no-such-ref --head HEAD
eq "error output says human" "$($RT --local --base no-such-ref --head HEAD | jq -r .tier)" "human"

# --pr mode against a fake gh: policy 404 vs outage, and a truncated file list
mkdir -p "$TMP/fb"; cat > "$TMP/fb/gh" <<'EOF'
#!/bin/bash
case "$*" in
  *"pulls/1/files"*) echo '[[{"filename":"web/a.tsx","status":"modified","patch":"+<b/>"}],[{"filename":"web/b.tsx","status":"modified","patch":"+<i/>"}]]';;
  "pr view 1 "*) echo "{\"baseRefName\":\"main\",\"changedFiles\":${FAKE_CHANGED:-2}}";;
  *"contents/.review-tiers"*)
    case "$FAKE_POLICY" in
      ok) printf 'default human\nagent web/**\n';;
      404) echo "gh: Not Found (HTTP 404)" >&2; exit 1;;
      *) echo "gh: Server Error (HTTP 502)" >&2; exit 1;;
    esac;;
  *) exit 1;;
esac
EOF
chmod +x "$TMP/fb/gh"
prt() { PATH="$TMP/fb:$PATH" $RT --pr o/r 1 2>/dev/null; }
eq "PR mode: UI change under a policy is agent" "$(FAKE_POLICY=ok prt | jq -r .tier)" "agent"
eq "PR mode: policy 404 means policy_found=false (tiering off upstream)" "$(FAKE_POLICY=404 prt | jq -r .policy_found)" "false"
eq "PR mode: a policy present means policy_found=true" "$(FAKE_POLICY=ok prt | jq -r .policy_found)" "true"
eq "PR mode: an outage is not 'no policy' (policy_found is not false)" "$(FAKE_POLICY=502 prt | jq -r .policy_found)" "null"
eq "PR mode: policy fetch outage fails closed to human" "$(FAKE_POLICY=502 prt | jq -r .tier)" "human"
ok "PR mode: an outage is NOT reported as 'no policy'" bash -c "! grep -q 'no .review-tiers' <<<\"\$1\"" _ "$(FAKE_POLICY=502 prt)"
eq "PR mode: truncated file list is human" "$(FAKE_POLICY=ok FAKE_CHANGED=3500 prt | jq -r .tier)" "human"
finish
