# Testing: making agent-written code trustworthy

Agents write code fast. Tests are how you know it's right. The trap is tests that pass by construction:
hard-coded answers, weakened assertions, regenerated snapshots. This guide is the setup that makes good tests the
easy path and gamed tests hard. Sources, all read 2026-10-09, are in `docs/research/RESEARCH-TESTING-2026-10-09.md`.

## The loop (what lanes do by default)

1. **Write the failing test first, and watch it fail for an assertion reason.** An import error doesn't count.
   Anthropic's guidance: "write a failing test that reproduces the issue, then fix it."
2. **Lock the tests** for the implement step: `! ~/.claude/kit/bin/tests-lock.sh on`. While `.claude/tests-locked` exists,
   Claude can't edit test files, and sessions can't lift the lock. Measured: read-only tests keep real
   performance while stopping agents editing tests to get green (ImpossibleBench, arXiv 2510.20270).
3. **Implement until green.** The Stop hook won't let a turn end while your checks fail.
4. **Unlock** (`! ~/.claude/kit/bin/tests-lock.sh off`), open the PR. The verifier reviews it; the review tier flags anything
   that weakened the tests.

The lane role carries Anthropic's published anti-hardcoding rule: tests verify correctness and don't define the
solution; no code that only works for the test inputs; "if any of the tests are incorrect, please inform me rather
than working around them." Giving the model that way out measurably reduced test-gaming in ImpossibleBench.

## What gets flagged to a person (review tiers)

Whatever the path, these turn a change `human` (`bin/review_tier.py`):
- a test file deleted, assertions removed, or a test newly `skip`/`xfail`/`.only`;
- a snapshot or golden file rewritten. Jest's own docs warn against regenerating snapshots instead of finding
  the cause;
- a new coverage, mutation or lint exclusion (`pragma: no cover`, `pragma: no mutate`, `istanbul ignore`,
  `eslint-disable`, `nosec`);
- a test marked flaky or given retries.

## Fast checks before "done": `.claude/check`

In a repo you've trusted (`~/.claude/kit/bin/trust-repo.sh <repo>`, because the check runs that repo's code), the Stop hook
runs `.claude/check` if it exists (otherwise `make check`, otherwise `npm test`).
Keep it fast, ideally under 90 seconds, by running the tests affected by the change. The full suite runs in CI.

```sh
#!/bin/bash
# .claude/check: affected tests only; CI runs everything.
set -e
# Python (pytest-testmon selects tests affected by changed code):
pytest --testmon -q
# JavaScript/TypeScript, use one:
#   npx jest --findRelatedTests $(git diff --name-only HEAD) --passWithNoTests
#   npx vitest related $(git diff --name-only HEAD) --run
```
Make it executable: `chmod +x .claude/check`.

## In CI: judge only what changed

`examples/ci/project-ci.yml` is a template. These steps were taken from the tools' docs but not run here, so
adapt them to your project.
- **Diff coverage:** `diff-cover coverage.xml --compare-branch=origin/main --fail-under=90` fails if the lines
  this PR changed aren't covered. A global coverage % is a weak signal; changed-line coverage is a useful one.
- **Mutation on changed code:** coverage proves a line ran, not that a test would notice it breaking. Mutation
  testing flips operators and drops lines, and checks that a test fails each time. Run it on the PR's changed
  code only:
  - Python: Cosmic Ray with its git filter (`cr-filter-git`);
  - JS/TS: Stryker `--incremental`;
  - Rust: cargo-mutants `--in-diff`;
  - Go: gremlins `--diff`.
  mutmut can't target changed lines, only name globs. Never run mutation inside the Stop hook; it's too slow.
- **Flaky tests:** retries only for tests on a quarantine list with an owner, never blanket `--reruns`, which
  hides real failures.

## Optional, high value

- **Property-based tests** for parsers, serializers and pure logic: Hypothesis (Python), fast-check (JS/TS). They're
  hard to special-case. With `CI` set, Hypothesis runs a derandomized profile, so the gate stays deterministic.
- **Separate test author and implementer:** one session writes the tests, another implements, as Anthropic's docs
  suggest ("have one Claude write tests, then another write code to pass them"). Lanes make this easy.
- **Held-out acceptance tests** that the implementer never sees cut test-gaming to near zero, at some cost to
  performance. Use them for the highest-stakes work.

## Evaluating the setup itself (evals)

When you change a prompt, a hook, or the model, re-run a small private eval:
- 20–50 real tasks from your own history;
- each with tests the agent doesn't see (fail-before / pass-after, the SWE-bench shape);
- report pass@k, pass^k (all k tries pass) and cost.

Anthropic's evals guidance recommends starting small and from real failures. `examples/evals/README.md` has the
task format.

## How this kit tests itself

- `make check`: 544 test cases (2026-10-09). Hooks are driven with the JSON Claude Code sends; GitHub is a fake `gh`; the
  installer runs in a throwaway HOME. There are no model calls and no network.
- `tests/test_e2e.sh`: installs into a throwaway home and exercises every installed hook through its symlink.
- `make mutate`: every safety rule is removed on purpose, and the matching test must fail (174 mutants, all
  killed, 2026-10-09). A mutant only counts as killed when a test assertion fails; a crash is reported as an error, and every
  test file must pass unmutated first. A new rule needs a new mutant line in `tests/mutants.txt`.
- `bash tests/linux-in-docker.sh`: the same checks on Ubuntu (GNU tools). macOS ships bash 3.2 and BSD tools, so
  every script is written for both.
- CI runs the tests, lint and the mutation check on every pull request.

## Live check in real Claude Code (opt-in)

`bash tests/live-claude.sh` proves the hooks hold inside a real `claude -p` session, not just when the tests feed
them JSON. It is not run by `make check` or CI (the name isn't `test_*.sh`): it needs `claude` logged in and calls
the model, about $0.11 with haiku (2026-10-09, Claude Code 2.1.280).

- **Isolation:** the kit is copied to a scratch dir. Claude runs with `--setting-sources project,local` (your
  `~/.claude/settings.json` hooks don't load) and `--settings` naming the scratch hooks by absolute path; each hook
  runs with `HOME` set to a scratch home. Repos and their `origin` are local scratch paths. No hook writes to
  `~/.claude` (Claude Code itself still uses your login).
- **Only the hook stands in the way:** Claude runs in `bypassPermissions`. A control run with no hooks must let a
  push to main land, which proves the scenarios can fail.
- **Judged by side effects:** origin refs (`git ls-remote`), files on disk, and the hook's reason in the tool
  result. A scenario where Claude never tried the action is a FAIL, not a pass.
- **Scenarios:** push to main denied; push to a feature branch allowed; `pkill` denied; a write into `.claude/hooks`
  denied; the Stop hook blocks a commit while `.claude/check` is red; `.claude/tests-locked` denies an Edit to a
  test; a bare `git push` after a `cd` in an earlier call is judged on the branch it would really push.
- **What it caught:** two bugs the offline tests couldn't see, both now fixed with offline tests too. A stray
  shell error on the Stop hook's stderr made Claude Code end the turn instead of continuing, so the first block
  didn't hold; and a blocked session rewrote `.claude/check` to `exit 0` (on a branch, the hook now runs the main
  branch's committed check).
- **Knobs:** `KIT_DIR` (test another build), `LIVE_MODEL` (default haiku), `LIVE_MAX_USD` (stop above it, default
  2), `KEEP=1` (keep the scratch dir and the stream-json logs). It prints PASS/FAIL per scenario and the total cost,
  and exits non-zero on any FAIL.
