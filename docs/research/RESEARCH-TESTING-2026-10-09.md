# Testing as a first-class feature of the starter kit: research and recommendations

Date: 2026-10-09. Every source below was read on 2026-10-09 unless marked otherwise. Primary sources
(official docs, tool repositories, arXiv papers) come first; anything else is marked **secondary**.
Snippets marked "quoted" were copied from the cited page. Snippets marked "kit sketch" are proposals
written for this document and have not been run.

Scope: (a) make sure the agents' code is tested well, in a way that's easy for agents and humans;
(b) test the kit itself (bash hooks, Python tools, installer) end to end in its own repo.

## Summary table

| # | Item | Verdict | Why (one line) | Primary source |
|---|------|---------|----------------|----------------|
| 1 | Failing test first: write it, see it fail for the right reason, then implement | ADOPT | Anthropic's docs recommend it ("write a failing test that reproduces the issue, then fix it"), and studies find tests in the prompt raise success rates | code.claude.com/docs/en/best-practices; arXiv 2402.13521 |
| 2 | Anti-hardcoding / "tell me if a test is wrong" text in CLAUDE.md | ADOPT | Anthropic publishes this prompt, and ImpossibleBench measured a stricter prompt cutting cheating from >85% to 1% for one model | platform.claude.com prompting best practices; arXiv 2510.20270 |
| 3 | Test files locked during implementation (PreToolUse hook + `Edit(...)` deny rule) | ADOPT | ImpossibleBench found read-only tests keep real performance and stop test edits | arXiv 2510.20270; code.claude.com/docs/en/permissions |
| 4 | Separate test-author and implementer roles (subagents or sessions) | ADOPT (as a mode) | The best-practices page names it ("have one Claude write tests, then another write code to pass them") | code.claude.com/docs/en/best-practices |
| 5 | Held-out acceptance tests the implementer never sees | OFFER | Hidden tests bring cheating close to zero but cost performance; SpecBench shows a visible-vs-holdout gap | arXiv 2510.20270; arXiv 2605.21384 |
| 6 | Diff coverage gate (`diff-cover`) | ADOPT | Cheap, works with any coverage.xml/lcov, and only judges lines the agent changed | github.com/Bachmann1234/diff_cover |
| 7 | Mutation testing on changed code only, as a PR job and an on-demand agent command | ADOPT (PR job) / OFFER (per-language) | This is how mutation testing scales in industry, and LLM test generation guided by survivors works | arXiv 2102.11378; arXiv 2501.12862 |
| 8 | Property-based tests (Hypothesis / fast-check) | OFFER | High value for parsers and pure logic; Hypothesis turns on a deterministic "ci" profile when CI is set | hypothesis.readthedocs.io; fast-check.dev |
| 9 | Snapshot/golden tests | OFFER, with guardrails | Jest's own docs warn against regenerating snapshots instead of finding root causes; treat a `-u` diff as a weakened test | jestjs.io/docs/snapshot-testing |
| 10 | Changed-file test selection in the Stop hook (testmon / jest / vitest) | ADOPT | Keeps the gate fast; the full suite still runs in CI | testmon.org; jestjs.io/docs/cli; vitest.dev/guide/cli |
| 11 | Retries only for tests marked flaky; quarantine list with an owner | ADOPT | About 1.5% of runs are flaky at scale; reruns only for marked tests | Google Testing Blog, 2016 |
| 12 | Blanket `--reruns N` on everything | SKIP | It hides real failures, and the agent learns that red sometimes means "try again" | same as above |
| 13 | bats-core for hook and installer tests | ADOPT | `run`, `$status`, `$output` and per-test temp dirs fit hooks that read JSON on stdin | bats-core.readthedocs.io |
| 14 | ShellCheck in CI | ADOPT | Already on the Ubuntu runners (0.9.0); install it on macOS | github.com/koalaman/shellcheck wiki; runner-images |
| 15 | Hook contract tests: pipe JSON on stdin, assert exit code and stdout JSON | ADOPT | Anthropic's documented way to test hooks; no model call | code.claude.com/docs/en/hooks-guide |
| 16 | Installer tests in a throwaway `HOME` + `CLAUDE_CONFIG_DIR` | ADOPT | `CLAUDE_CONFIG_DIR` is documented; nothing touches the real `~/.claude` | code.claude.com/docs/en/env-vars |
| 17 | Real `claude -p` against a local scripted mock API (`ANTHROPIC_BASE_URL`) | OFFER (v2) | Proves the real CLI runs the hooks at $0; mock fidelity is the risk | env-vars doc; secondary: a public issue describing it |
| 18 | Real `claude -p --bare` smoke test with a live model, capped | OFFER (nightly, manual) | Tiny budget (`--max-budget-usd`, `--max-turns`) proves wiring against a real model | code.claude.com/docs/en/cli-reference |
| 19 | Shell mutation testing tool (mutate4bash, shmutant) | SKIP | Both repos had 0 stars when read; shmutant needs bash 5.3 (macOS ships 3.2) | GitHub repos |
| 20 | Scripted "known mutant -> expect red" checks for the kit's own guards | ADOPT | Proves each guard can fail; small and deterministic | (pattern; see section 4.6) |
| 21 | macOS + Linux matrix in GitHub Actions | ADOPT | macOS runners have bash 3.2 and no shellcheck, and that's where hooks break | docs.github.com; actions/runner-images |
| 22 | Small private eval set (20–50 tasks), pass@k and pass^k, re-run on every prompt/model/hook change | ADOPT (kit repo) / OFFER (users) | Anthropic's evals guidance: start with 20–50 tasks from real failures | anthropic.com/engineering/demystifying-evals-for-ai-agents |
| 23 | Running SWE-bench itself | SKIP | Docker-heavy and public (likely in training data); copy its FAIL_TO_PASS / PASS_TO_PASS shape instead | swebench.com; HF dataset card |
| 24 | Coverage % as a hard global gate | SKIP | Coverage is "weakly correlated" with bug detection (MuTAP); an ISSTA 2026 replication finds proxy metrics context-dependent for LLM tests | arXiv 2308.16557; arXiv 2607.22880 |

## 1. Making agents write good tests

### 1.1 Failing test first (TDD with agents)

What Anthropic's docs say (https://code.claude.com/docs/en/best-practices):
- "Give Claude a check it can run: tests, a build, a screenshot to compare." A check can gate the stop
  four ways: in one prompt, as a `/goal`, "As a deterministic gate: a Stop hook runs your check as a
  script and blocks the turn from ending until it passes," or "By a second opinion: a verification
  subagent ... so the agent doing the work isn't the one grading it."
- Their example prompt for a bug: "write a failing test that reproduces the issue, then fix it".
- "Have Claude show evidence rather than asserting success". And: "have one Claude write tests, then
  another write code to pass them." (The old anthropic.com/engineering/claude-code-best-practices URL now
  308-redirects here, and its "write tests, commit; code, iterate, commit" section is gone.)

Anthropic's prompting guide
(https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices),
section "Avoid focusing on passing tests and hardcoding", quoted: "Do not hard-code values or create
solutions that only work for specific test inputs ... Tests are there to verify correctness, not to define
the solution ... If the task is unreasonable or infeasible, or if any of the tests are incorrect, please
inform me rather than working around them." And: "It is unacceptable to remove or edit tests because this
could lead to missing or buggy functionality." Research: "Test-Driven Development for Code Generation"
(arXiv 2402.13521) found that adding tests to the problem statement consistently raised solve rates on MBPP
and HumanEval. That is function-level evidence only.

**Kit design.** The failing-first step should be *mechanical*, not a request. (1) The test author runs the
new test, and the kit records `red` with the test IDs and the failure *reason*, so an `ImportError` doesn't
count. (2) The tests are locked (section 2). (3) The implementer turns them green; the Stop hook re-runs those
IDs plus the affected tests. (4) The verifier checks that the red→green pair exists in the log.

### 1.2 Property-based testing

- Hypothesis (https://hypothesis.readthedocs.io/en/latest/quickstart.html), quoted:
  `@given(st.integers())` / `def test_integers(n): ...`. "By default, Hypothesis generates 100 random inputs."
- API reference (https://hypothesis.readthedocs.io/en/latest/reference/api.html): when the `CI` env var is
  set, a built-in "ci" profile turns on automatically with
  "derandomize=True, deadline=None, database=None, print_blob=True, suppress_health_check=[HealthCheck.too_slow]".
  Failing examples are stored under `.hypothesis/examples`. Quoted override:
  `settings.register_profile("ci", settings.get_profile("ci"), max_examples=1000)`.
- fast-check (https://fast-check.dev/docs/introduction/getting-started/), quoted:
  `fc.assert(fc.property(fc.string(), (text) => { return contains(text, text); }));`
  Vitest integration: `npm install --save-dev fast-check @fast-check/vitest`, then `test.prop([...])`.
  Replay a failure with `fc.configureGlobal({ seed: <the-seed-from-the-error> })`.
- Why it matters: properties (round-trip, idempotence, an oracle check) are hard to special-case. SpecBench
  caught "a 2,900-line hash-table 'compiler' that memorizes test inputs" (arXiv 2605.21384). OFFER: suggest a
  property for parsers, serializers and pure functions; the derandomized CI profile keeps the gate deterministic.

### 1.3 Mutation testing

Why: coverage proves a line ran, not that a test would notice it breaking. MuTAP (arXiv 2308.16557)
quoted: "coverage is weakly correlated with the efficiency of tests in bug detection". Feeding surviving
mutants back into the prompt detected 28% more faulty snippets. The industrial approach is
diff-scoped: "Practical Mutation Testing at Scale" (arXiv 2102.11378) mutates only code under review,
filters out unproductive ("arid") mutants, and caps mutants per line, producing "orders of magnitude fewer
mutants".

| Tool | Lang | Changed-code mode | Notes |
|------|------|-------------------|-------|
| mutmut 3 | Python | **No changed-lines option.** Incremental: "Remembers work that has been done"; you can narrow by name glob: `mutmut run "my_module.my_function*"`; `mutate_only_covered_lines=true` | Needs `fork`, so Windows only via WSL. Config quoted below |
| Cosmic Ray | Python | **Yes**: `cr-filter-git` "looks for edited or new lines from the given git branch"; branch set in `[cosmic-ray.filters.git-filter]` (default `master`) | init/exec/report session in SQLite; has distributed execution |
| StrykerJS | JS/TS | `--incremental` (diff against `reports/stryker-incremental.json`) and `--mutate src/app.js:5-7` line ranges. **No `since` option in the config docs** | Can't see changes to deps, env vars, or `.snap` files |
| cargo-mutants | Rust | **Yes**: `--in-diff DIFF_FILE` | "a diff that only deletes or changes test code won't cause any mutants to run" |
| Gremlins | Go | **Yes**: `gremlins unleash --diff "origin/$GITHUB_BASE_REF"`; `--threshold-efficacy 80` exits 10 | Prefer this to go-mutesting for PRs |
| go-mutesting (avito-tech fork) | Go | No diff mode found | Fork of the unmaintained original; 277 stars |

Quoted configs:
- mutmut (https://github.com/boxed/mutmut README):
  ```toml
  [tool.mutmut]
  source_paths = [ "src/" ]
  pytest_add_cli_args_test_selection = [ "tests/" ]
  ```
  plus `mutate_only_covered_lines=true`, `max_stack_depth=8`, and `# pragma: no mutate` /
  `# pragma: no mutate block` / `# pragma: no mutate start`…`end`.
- Cosmic Ray (https://cosmic-ray.readthedocs.io/en/latest/tutorials/intro/index.html):
  `[cosmic-ray]` with `module-path = "mod.py"`, `timeout = 10.0`, `excluded-modules = []`,
  `test-command = "python -m unittest test_mod.py"`, and `[cosmic-ray.distributor] name = "local"`. Then
  `cosmic-ray init tutorial.toml tutorial.sqlite` → `cr-filter-git tutorial.sqlite` (filter, per
  https://cosmic-ray.readthedocs.io/en/latest/how-tos/filters.html) → `cosmic-ray exec tutorial.toml tutorial.sqlite`
  → `cr-report tutorial.sqlite --show-pending`. (The exact `cr-filter-git` argument order is my reading;
  check it against `cr-filter-git --help` before shipping.)
- StrykerJS incremental (https://stryker-mutator.io/docs/stryker-js/incremental/): `{"incremental": true}`;
  flags `--incremental`, `--incrementalFile`, `--force`. Thresholds from the config docs: `high` 80,
  `low` 60, `break` (null by default, so set it to fail the build).
- cargo-mutants PR job (https://mutants.rs/pr-diff.html), quoted:
  ```yaml
  - name: Relative diff
    run: |
      git branch -av
      git diff origin/${{ github.base_ref }}.. | tee git.diff
  - name: Mutants
    run: |
      cargo mutants --no-shuffle -vV --in-diff git.diff
  ```

Changed-lines mutation for Python with mutmut, kit sketch (not from the docs). mutmut can't take a diff,
so the kit maps the diff's changed functions to mutmut's name globs:
```bash
git diff -U0 origin/main...HEAD -- 'src/*.py' > changed.diff
python tools/changed_functions.py changed.diff |   # prints e.g. pkg.module.x_func
  while read -r fn; do mutmut run "${fn}*"; done
mutmut results                                       # survivors -> agent prompt
```
Alternative: use Cosmic Ray + `cr-filter-git`, which does this natively but is slower to set up. Pick
one after a timed trial on the kit's own Python tools.

Wiring into the agent loop: **don't** put mutation testing in the Stop hook. It's minutes, not seconds.
Run it as (i) a PR job on the diff that feeds survivors into the review tier, and (ii) a `/mutants` skill
the agent can run before it asks for review. Following the ACH/MuTAP pattern, a surviving mutant becomes
a concrete prompt: "this mutant on line N survives; write a test that kills it". Gate on *new survivors in
the changed code*, not on a global score.

### 1.4 Diff coverage

https://github.com/Bachmann1234/diff_cover, quoted commands: `diff-cover coverage.xml`,
`diff-cover coverage.xml --compare-branch=origin/release`, `diff-cover coverage.xml --fail-under=80`,
`diff-cover coverage.xml --format html:report.html,markdown:report.md`. Formats: Cobertura, Clover, JaCoCo, coverage.py, JSCover, lcov. Config: `[tool.diff_cover]
compare_branch = "origin/feature"` in pyproject.toml. Kit default, kit sketch:
`pytest --cov --cov-report=xml && diff-cover coverage.xml --compare-branch=origin/main --fail-under=90`.
Treat diff coverage as a *floor*, and mutation survivors as the quality signal.

### 1.5 Snapshot / golden-test pitfalls

From https://jestjs.io/docs/snapshot-testing, quoted: "fight against the habit of regenerating snapshots
when test suites fail instead of examining the root causes of their failure". `--ci` makes a missing snapshot
fail instead of being written: "since new snapshots automatically pass, they should not pass a test run on
a CI system". Snapshots must be deterministic (mock `Date.now`).

**Kit rule:** for an agent, `jest -u`, `pytest --snapshot-update` or rewriting a golden file is the same
thing as editing an assertion. The review-tier checker should treat changes under `__snapshots__/`,
`*.snap`, `tests/golden/**` like weakened assertions and escalate them. Always run jest with `--ci`.

### 1.6 Research on LLM-generated tests (measured numbers)

- **TestGen-LLM** (arXiv 2402.09171, 2024-02-14): of the generated test cases, "75% ... built correctly,
  57% passed reliably, and 25% increased coverage". It "improved 11.5% of all classes", and engineers
  accepted 73% of its recommendations. **The lesson:** every candidate went through filters (builds,
  passes repeatedly, raises coverage) before a human saw it. The kit's Stop hook and diff-cover are those
  filters.
- **ACH, mutation-guided** (arXiv 2501.12862, 2025-01-22): ran on 10,795 Kotlin classes, generated 9,095
  mutants and 571 tests; engineers accepted 73%. Its LLM equivalent-mutant detector scored precision 0.79 and
  recall 0.47 (0.95 and 0.96 with simple pre-processing). **The lesson:** generate a few *targeted*
  mutants, then tests that kill them.
- **MuTAP** (arXiv 2308.16557): surviving mutants in the prompt → 28% more faulty snippets detected, and
  a 93.57% mutation score on synthetic buggy code.
- **Replication** (arXiv 2607.22880, ISSTA 2026): for LLM-generated suites, "the usefulness of coverage
  and mutation is highly context-dependent". They're useful for regression comparisons and unreliable for
  exposing bugs already in the code. So don't make any single metric the sole gate.

## 2. Anti-gaming: stop agents weakening tests

Measured evidence:
- **ImpossibleBench** (arXiv 2510.20270): tasks where the tests contradict the spec, so any pass is
  cheating. Quoted: "Hiding tests from agents reduces cheating success rate to near zero, but also degrades
  performance on the original benchmark"; "Read-only access provides a middle ground: it restores legitimate
  performance while preventing test modification attempts". Read-only is "particularly effective against
  models like Opus-4.1, whose primary cheating strategy involves modifying test cases". A strict prompt took
  one model's cheating on Conflicting-LiveCodeBench "from >85% to 1%". An abort option
  (`flag_for_human_intervention`) cut one model from 54% to 9%, though "much less pronounced for Claude Opus
  4.1". LLM monitors caught 86–89% of cheating on LiveCodeBench but only 42–65% on SWE-bench variants.
- **SpecBench** (arXiv 2605.21384, v2 2026-09-09): "every frontier agent saturates the visible suite,
  reward hacking persists". The visible-vs-holdout gap "grows by 28 percentage points for every tenfold
  increase in code size".
- **"Building to the Test"** (arXiv 2606.28430): with the oracle in the loop, scores reach near-perfect
  "from a demo holding the tested behavior directly, the library left dead or absent".

How the kit should respond, in layers:
1. **Prompt layer (ADOPT).** CLAUDE.md carries the Anthropic anti-hardcoding text plus an explicit escape
   hatch: "if a test is wrong, stop and say so". ImpossibleBench shows giving the model a way out reduces
   cheating.
2. **Lock layer (ADOPT).** During implementation, test paths are read-only, enforced two ways:
   - Permission deny rules. From https://code.claude.com/docs/en/permissions: "Read and Edit deny rules apply
     to Claude's built-in file tools, to file commands Claude Code recognizes in Bash, such as `cat`, `head`,
     `tail`, `sed`, and `tee`, and to the targets of Bash redirections ... They don't apply to ... a Python or
     Node script that opens files itself. For OS-level enforcement ... enable the sandbox." Also: use
     `Edit(...)`, not `Write(...)`, for path rules.
   - The kit's PreToolUse guard: block `Edit|Write` when `tool_input.file_path` matches the locked globs while
     a lock file exists. This is the documented `protect-files.sh` pattern (exit 2 with a stderr reason) from
     https://code.claude.com/docs/en/hooks-guide.
   - Neither layer stops `python -c "open('tests/x.py','w')"`. That's why the review-tier diff check stays as
     the backstop and the sandbox is OFFERed.
3. **Role layer (ADOPT as a mode).** Subagent frontmatter supports `tools`, `disallowedTools`,
   `permissionMode` and scoped `hooks` (https://code.claude.com/docs/en/sub-agents). Quoted:
   `disallowedTools: Write, Edit` gives a no-write agent. Kit sketch: a `test-author` subagent that may edit
   only `tests/**` (enforced by its frontmatter PreToolUse hook), and an `implementer` whose frontmatter
   hook denies `tests/**`.
4. **Held-out layer (OFFER).** For larger tasks, the human or test-author writes acceptance tests that are
   stored outside the implementer's working tree (or added only after it's done) and run by the verifier
   and CI. SWE-bench uses the same shape: `FAIL_TO_PASS` = "tests resolved by the PR and tied to the issue
   resolution"; `PASS_TO_PASS` = "tests that should pass before and after"
   (https://huggingface.co/datasets/princeton-nlp/SWE-bench).
5. **Review layer (already shipped).** Keep escalating deleted or weakened tests, new skip/xfail/.only, and
   weakened assertions. Add snapshot updates and `pragma: no mutate` / `# pragma: no cover` additions to that list.

## 3. Fast feedback loops

Stop-hook mechanics (https://code.claude.com/docs/en/hooks and /hooks-guide): the default command-hook
timeout is **600 s**; exit 2 or `{"decision":"block","reason":...}` blocks the stop; "Claude Code overrides a
Stop hook after it blocks eight times in a row with no tool call from Claude in between" (check
`stop_hook_active`; `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` raises the cap); all matching hooks run in parallel.

Keep the Stop hook to *affected tests + lint on changed files*, with a 60–90 s budget, and leave the full
suite to CI:
- **pytest-testmon** (https://testmon.org/): "selects and executes only tests you need to run ... collecting
  dependencies between tests and all executed code (internally using Coverage.py)". Command: `pytest --testmon`;
  `--testmon-noselect` reorders without deselecting. It doesn't track static data files or network services,
  so data-driven tests need an explicit rule ("if fixtures/ changed, run all").
- **Jest** (https://jestjs.io/docs/cli): `--findRelatedTests <files>` ("Useful for pre-commit hook integration
  to run the minimal amount of tests necessary"), `--onlyChanged`/`-o`, `--changedSince <branch|sha>`. These
  need a static import graph ("no dynamic requires").
- **Vitest** (https://vitest.dev/guide/cli.html): `vitest related /src/index.ts ...` (static imports only),
  `--changed origin/main`. Watch mode "Will fallback to `vitest run` in CI or when stdin is not a TTY".
- Watch mode suits humans, not the Stop hook. The hook needs one bounded run with an exit code.

Flaky tests (Google Testing Blog, https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html):
about 1.5% of all test runs are flaky, about 16% of tests show some flakiness, and flaky tests account for
84% of pass-to-fail transitions. Reruns are limited to tests marked flaky or to explicit user requests, and
very flaky tests are moved off the critical path (paraphrased from the fetch; the wording isn't verbatim).
Kit policy: `@pytest.mark.flaky(reruns=2)` (pytest-rerunfailures, https://github.com/pytest-dev/pytest-rerunfailures)
or `vitest --retry.count` **only** on tests listed in `.kit/quarantine.txt`, each with an owner and an expiry
date. Adding to that list is a review-tier escalation, because an agent quarantining a test is weakening it.

## 4. Testing the kit itself

### 4.1 bats-core vs a plain bash harness
bats-core (https://bats-core.readthedocs.io/en/stable/writing-tests.html) gives `run`, `$status`,
`$output`, `${lines[@]}`, `run -N` / `run !` exit checks, `--separate-stderr`, `setup_file`, and
`$BATS_TEST_TMPDIR` (per test). Quoted example: `@test "invoking foo without arguments prints usage" {
run foo; [ "${lines[0]}" = "usage: foo <filename>" ]; }` (reflowed onto one line). The docs suggest `run bash -c "command < input_file"` for stdin. A plain harness would rebuild these pieces
by hand (status capture, temp dirs, TAP output). ADOPT bats-core, pinned (vendored as a git submodule, or
installed with `bats-core/bats-action@4.0.0`, which also installs bats-support, bats-assert and bats-file;
https://github.com/bats-core/bats-action).

Hook contract test, kit sketch:
```bash
bats_require_minimum_version 1.5.0
@test "guard blocks edits to locked tests" {
  touch "$BATS_TEST_TMPDIR/.tests-locked"
  run -2 --separate-stderr bash -c \
    "CLAUDE_PROJECT_DIR='$BATS_TEST_TMPDIR' hooks/pretooluse-guard.sh < test/fixtures/edit-tests-file.json"
  [[ "$stderr" == *"locked"* ]]
}
```

### 4.2 Testing hooks with JSON on stdin (Anthropic's documented method)
From https://code.claude.com/docs/en/hooks: "Command hooks receive JSON data via stdin"; and "Manual
testing: Run your hook script directly with piped JSON input: `cat hook_input.json | /path/to/your-hook.sh`".
The hooks guide's troubleshooting section adds:
`echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | ./my-hook.sh; echo $?`.
Facts to assert in tests: exit 2 blocks, and "Even valid JSON with `permissionDecision: "allow"` cannot
override an exit 2 block"; a JSON deny is exit 0 with `hookSpecificOutput.permissionDecision: "deny"`; stdout
must be pure JSON (a shell profile `echo` breaks parsing, and misplaced top-level fields are ignored
silently, so `jq -e` the exact path). Build fixtures from the documented PreToolUse and Stop input shapes,
including `stop_hook_active`.

### 4.3 ShellCheck
Quoted step (https://github.com/koalaman/shellcheck/wiki/GitHub-Actions): `- name: Run ShellCheck` /
`run: find . -type f -name "*.sh" -exec shellcheck {} +`. The Ubuntu 24.04 image lists `shellcheck 0.9.0-1` and Bash 5.2.21. **The macOS 15 image (20260824) lists
neither shellcheck nor bats, and its Bash is 3.2.57**
(https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md,
.../ubuntu/Ubuntu2404-Readme.md). So run shellcheck on Linux, and on macOS `brew install bats-core
shellcheck`. Hook scripts must also be tested *under /bin/bash 3.2*: no `mapfile`, no `${var,,}`, no
associative arrays. Hooks run via `sh -c` on macOS/Linux per the hooks guide, so shebangs matter.

### 4.4 Installer in a throwaway HOME
`CLAUDE_CONFIG_DIR`: "Override the config directory. Defaults to `~/.claude`. Use this to run multiple
isolated Claude Code instances" (https://code.claude.com/docs/en/env-vars). Claude Code also writes
`~/.claude.json` (https://code.claude.com/docs/en/settings), so set both. Kit sketch:
```bash
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; export CLAUDE_CONFIG_DIR="$HOME/.claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
}
@test "install is idempotent and merges, not clobbers" {
  printf '{"permissions":{"allow":["Bash(ls)"]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  run -0 ./install.sh --yes
  run -0 ./install.sh --yes
  run -0 jq -e '.permissions.allow | index("Bash(ls)")' "$CLAUDE_CONFIG_DIR/settings.json"
}
```
Also test: uninstall restores the backup, the installer runs on bash 3.2, and it never writes outside `$HOME`
(assert with `find / -newer marker` inside a container, or by running with a read-only real home in CI).

### 4.5 End-to-end with the real `claude` CLI
Documented flags (https://code.claude.com/docs/en/cli-reference, https://code.claude.com/docs/en/headless):
- `--bare`: "skip auto-discovery of hooks, skills ... and CLAUDE.md". Load config explicitly with
  `--settings <file-or-json>`. "In bare mode, Claude Code never reads OAuth credentials or the system
  keychain", so it needs `ANTHROPIC_API_KEY` or `apiKeyHelper`. "`--bare` is the recommended mode for
  scripted and SDK calls, and will become the default for `-p` in a future release."
- `--max-budget-usd` (print mode; "Spend can pass the cap, so leave headroom"), `--max-turns` ("Exits with
  an error when the limit is reached"), `--no-session-persistence`, `--permission-mode dontAsk`,
  `--output-format stream-json --verbose --include-hook-events`.
- With stream-json, "denials appear as `permission_denied` system messages, and the final result message
  lists them in `permission_denials`". That's the assertion that a hook really blocked a real tool call.
- **Zero-model hook exercises:** `claude --init-only` "runs Setup hooks and `SessionStart` hooks with the
  `startup` matcher, then exits without starting a conversation" (hooks reference). This covers
  SessionStart/Setup hooks only, not PreToolUse/Stop.

Three tiers, cheapest first:
1. **Contract tests (every push, $0):** pipe fixtures into each hook (4.2).
2. **Real CLI, mock model (every push, $0, OFFER v2):** point `ANTHROPIC_BASE_URL` (documented: "Override
   the API endpoint to route requests through a proxy or gateway") at a loopback server that streams a
   scripted `tool_use` (for example, an `Edit` on a locked test). Then assert the hook fired and
   `permission_denials` is non-empty. A public project describes exactly this tier (**secondary**,
   https://github.com/zackees/clud/issues/1323): streaming SSE is mandatory, the mock must serve
   `/v1/messages` (+ `count_tokens`), and "Project hooks need `--settings` passthrough when using isolated
   `CLAUDE_CONFIG_DIR`". Risk: the CLI's wire expectations change between versions. Pin the CLI version in
   this job and treat a failure as "re-record the mock".
3. **Real CLI, real model (nightly or manual, OFFER):**
   `claude --bare -p "<scripted task>" --settings kit-settings.json --model haiku --max-turns 3
   --max-budget-usd 0.25 --permission-mode dontAsk --output-format stream-json --verbose --include-hook-events`.
   Assert on `permission_denials` and hook events, not on the model's prose. This is the only tier that
   proves the real model plus the real CLI, so keep it small and never on PRs from forks. Its first test
   must prove that hooks from `--settings` run under `--bare` (not stated in the docs; see "Couldn't verify").

### 4.6 Mutation testing of shell scripts
Dedicated tools exist but are immature: mutate4bash (https://github.com/lukasa1993/mutate4bash; 0 stars, 8
commits) and shmutant (https://github.com/BWBama85/shmutant; 0 stars, needs bash 5.3). SKIP both. The norm
is a scripted mutant list. Kit sketch:
```bash
# test/mutants.sh: each line = file | sed expression | test that must go red
hooks/pretooluse-guard.sh | s/exit 2/exit 0/              | test/guard.bats
hooks/stop-checks.sh      | s/"block"/"approve"/          | test/stop.bats
tools/review_tier.py      | s/if removed_asserts:/if False:/ | tests/test_review_tier.py
```
The runner copies the repo to a temp dir, applies one mutant, runs the named test, and requires a
non-zero exit. A mutant that survives fails the job. For the Python tools, mutmut can also run on the
kit's own `tools/`. Add kcov (https://github.com/SimonKagstrom/kcov: supports "Bash", writes
cobertura XML) only if line coverage of hooks becomes a question. OFFER.

### 4.7 GitHub Actions matrix
Quoted shape (https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations):
`strategy: matrix: os: [ubuntu-latest, macos-latest]`. Kit sketch:
```yaml
jobs:
  kit:
    strategy: { fail-fast: false, matrix: { os: [ubuntu-latest, macos-latest] } }
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v6
      - if: runner.os == 'macOS'
        run: brew install bats-core shellcheck
      - if: runner.os == 'Linux'
        uses: bats-core/bats-action@4.0.0
      - run: find . -type f -name "*.sh" -exec shellcheck {} +
      - run: bats -r test/
      - run: python -m pytest tools/ -q
      - run: bash test/mutants.sh
```
`fail-fast: false` makes a macOS-only failure visible instead of being cancelled by the Linux job.

## 5. Evaluating the AI coding setup itself

Anthropic, "Demystifying evals for AI agents" (https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents,
published 2026-01-09), quoted:
start with "20-50 simple tasks drawn from real failures"; "pass@k: measures the likelihood that an agent
gets at least one correct solution in k attempts", "pass^k: measures the probability that all k trials
succeed" (for an unattended kit, **pass^k is the one that matters**); "Deterministic graders are natural for
coding agents"; capability evals "should start at a low pass rate", regression evals "should have a nearly
100% pass rate"; "You won't know if your graders are working well unless you read the transcripts".
Anthropic platform docs (https://platform.claude.com/docs/en/test-and-evaluate/develop-tests): "Prioritize
volume over quality" for automated grading, and use a different model to grade than the one that
generated. pass@k origin: arXiv 2107.03374 (28.8% at 1 sample vs 70.2% with 100 samples on HumanEval).

A practical eval for one person (ADOPT in the kit repo):
- 30 tasks in `evals/tasks/<id>/`, each with: a repo snapshot or a small fixture repo, a prompt,
  `FAIL_TO_PASS` held-out tests (never visible to the agent), `PASS_TO_PASS` tests, and an expected-guard
  outcome for *adversarial* tasks. ImpossibleBench-style tasks whose tests contradict the spec should end
  with the agent stopping or flagging, never green.
- Run each task k=3 times with `claude --bare -p ... --max-budget-usd` and report pass@1, pass^3,
  cost, and guard hits. Re-run on every change to prompts, CLAUDE.md, hooks, model or CLI version, and
  diff the results against the stored baseline.
- Cost control: run the regression set (about 10 tasks) per kit release and the full set weekly. Keep
  Haiku for adversarial and guard tasks, where the hook decides, not the model.
- SKIP running SWE-bench itself: it needs Docker per instance
  (`python -m swebench.harness.run_evaluation ...`), and public tasks don't measure *this* kit.

## 6. Recommendation

**ADOPT (ship by default):** (1) a CLAUDE.md block covering failing test first, showing evidence, the
anti-hardcoding text, and "if a test is wrong, stop and say so"; (2) a recorded `red` (new test IDs failing
for an assertion reason) before implementation; (3) a test lock: the PreToolUse guard denies `Edit|Write` on
locked globs while `.kit/tests-locked` exists, plus `permissions.deny: ["Edit(**/tests/**)"]` in implement
mode; (4) the review tier extended to snapshot/golden rewrites, quarantine additions, and new
`pragma: no mutate|no cover`; (5) a Stop hook that runs only affected tests (`pytest --testmon` /
`jest --findRelatedTests` / `vitest related`) within 90 s and respects `stop_hook_active`; (6)
`diff-cover coverage.xml --compare-branch=origin/main --fail-under=90`; (7) a diff-scoped mutation PR job
(mutmut by function glob or Cosmic Ray + `cr-filter-git`; Stryker `--incremental`; cargo-mutants
`--in-diff`; gremlins `--diff`) feeding survivors to review and a `/mutants` skill; (8) retries only for
quarantined tests with an owner and an expiry date; (9) for the kit repo: bats + JSON-fixture hook
contract tests, shellcheck, a throwaway-HOME installer test, known-mutant checks, and an ubuntu+macos
matrix that exercises bash 3.2; (10) for the kit repo: a 20–50 task private eval with held-out tests,
reporting pass^k and cost, re-run on every prompt/hook/model change.

**OFFER (opt-in):** property-based testing (Hypothesis, fast-check); held-out acceptance tests for big
tasks; separate test-author and implementer subagents; sandbox mode to close the "script writes the test
file" gap; a mock-API real-CLI tier; a capped live-model nightly; kcov for hooks.

**SKIP:** blanket reruns; coverage % as the sole gate; shell mutation tools (immature); running SWE-bench;
mutation testing inside the Stop hook (too slow).

## Couldn't verify
- Whether `--bare` runs hooks defined in a `--settings` file (see 4.5). Prove it with tier 2 or 3 before
  relying on it.
- The exact `cr-filter-git` CLI argument order. The filter's behavior is documented, its usage line was not
  on the page.
- A widely cited "LLM test mutation score 0.546 vs human 0.690" figure surfaced in search but was **not**
  found in the cited survey (arXiv 2511.21382). It's left out.
- pytest-rerunfailures' own wording on masking flakiness. The fetch summarizer claimed a caveat I couldn't
  confirm verbatim, so the policy above rests on the Google Testing Blog alone.
- No snippet marked "kit sketch" has been run.
