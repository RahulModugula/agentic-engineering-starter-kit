# Testing: making agent-written code trustworthy

Agents write code fast. Tests are how you know it's right. The trap is tests that pass by construction:
hard-coded answers, weakened assertions, regenerated snapshots. This guide is the setup that makes good tests the
easy path and gamed tests hard. Sources, all read 2026-10-09, are in `docs/research/RESEARCH-TESTING-2026-10-09.md`.

## The loop (what lanes do by default)

1. **Write the failing test first, and watch it fail for an assertion reason.** An import error doesn't count.
   Anthropic's guidance: "write a failing test that reproduces the issue, then fix it."
2. **Lock the tests** for the implement step: `! $KIT/bin/tests-lock.sh on`. While `.claude/tests-locked` exists,
   Claude can't edit test files, and sessions can't lift the lock. Measured: read-only tests keep real
   performance while stopping agents editing tests to get green (ImpossibleBench, arXiv 2510.20270).
3. **Implement until green.** The Stop hook won't let a turn end while your checks fail.
4. **Unlock** (`! $KIT/bin/tests-lock.sh off`), open the PR. The verifier reviews it; the review tier flags anything
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

In a repo you've trusted (`$KIT/bin/trust-repo.sh <repo>`, because the check runs that repo's code), the Stop hook
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

- `make check`: over 340 test cases. Hooks are driven with the JSON Claude Code sends; GitHub is a fake `gh`; the
  installer runs in a throwaway HOME. There are no model calls and no network.
- `tests/test_e2e.sh`: installs into a throwaway home and exercises every installed hook through its symlink.
- `make mutate`: every safety rule is removed on purpose, and the matching test must fail (72 mutants, all
  killed). A new rule needs a new mutant line in `tests/mutants.txt`.
- CI (personal repo): Ubuntu and macOS. macOS runners ship bash 3.2, so every hook is written for it.
