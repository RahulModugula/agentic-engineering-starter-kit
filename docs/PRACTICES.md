# Engineering practices, graded by evidence

What to do in a repository that agents and people both change, and how much each recommendation is worth. Read
2026-11-18. The kit's hooks and gates enforce a few of these; this page is the reasoning, and it says plainly where
the evidence is thin. `docs/TESTING.md` covers tests, `docs/REFACTORING.md` the behaviour-neutral refactor protocol,
and `templates/` has copy-ready files.

**Grades.** A: replicated or controlled. B: one rigorous study or a large public dataset. C: vendor, expert or
official guidance. D: anecdote. "Measured here" means our own count in one production Python codebase (about 38,500
tests, eight refactor waves), with n and date when we have them; it is evidence about that codebase only. A number
marked *secondary* was read from a summary or excerpt and not traced to the primary paper: treat it as a lead.
Nothing below is graded A. No grade here has been raised above what its source supports.

## 1. Principles

1. **Enforce with code, advise with prose.** A rule that must always hold goes in a test, linter, hook or CI
   check. Prose is advisory. (C: vendor guidance.)
2. **Prove behaviour, don't assert it.** In a differential-fuzzing study of LLM refactorings, 19-35% were not
   equivalent, and about 21% of those still passed the existing tests (B: Dristi and Dwyer, arXiv 2602.15761;
   preprint, one group, comparison method under-specified; read from the paper's text, *secondary* for the exact
   rates). So pin behaviour first, change, then compare. (Measured here: recorded goldens caught two real defects
   across waves 5-8.)
3. **The agent that writes a change never grades it.** Use a fresh-context reviewer that sees the diff and the
   criteria. (C. Measured here: two improvement batches each failed independent review once and were fixed.)
4. **Agents game tests.** Locking the tests and giving the agent an explicit "this task is impossible" exit cut
   cheating from 54% to 9% on conflicting-test tasks (B: ImpossibleBench, arXiv 2510.20270; *secondary*, and one
   audit of a long report found its figures attributed to three different papers, so verify before quoting).
   Never let the implementing agent edit the tests it is judged by without a stated reason in the diff.
5. **Soft first, hard only with evidence.** A new check starts as a report. It becomes blocking only when it guards
   a failure that has already recurred in this repo's own history. (A policy decision, not research. See section 5.)
6. **Ratchets, not thresholds.** A baseline that may only shrink beats a global cap nobody can meet on legacy code.
   Every rise is listed in the PR by file and number. (Measured here: a complexity baseline went from 297 to 36
   entries over eight waves with no loosening.) `bin/ratchet.py` is a small generic one.
7. **Keep always-on context small.** Repository context files gave no success gain and over 20% extra cost in one
   study (B: arXiv 2602.11988; **a single, unreplicated study**; human-written files were slightly better than
   LLM-generated ones). A second, smaller study found shorter runtime with a root AGENTS.md but did not measure
   correctness (C: arXiv 2601.20404, workshop paper, 124 PRs). So: a short file, commands and non-obvious rules
   only, no layout tree, no copy of the README. Turn a *repeated* mistake into a guard, not into another note.
8. **Measure your own setup.** Experienced developers were 19% slower with early-2025 AI tools while believing they
   were faster (B: METR randomised trial, 16 developers, 246 tasks, arXiv 2507.09089; narrow setting and old
   models). Run paired with/without comparisons on your real tasks before standardising a workflow (section 7).

## 2. What the evidence supports

| Topic | Finding | Grade | Source (read 2026-11-18) | Caveat |
|---|---|---|---|---|
| Complexity | Functions over 10 decision points are hard to test; AI-marked commits were 17% more likely to add one; decision points per 100 new lines rose 5.2 to 8.1 after AI adoption in 27 of 30 repos | B-/C | A 201,576-commit vendor study, read via a forum summary (*secondary*) | Observational, vendor, no causation |
| Complexity | McCabe 10 is a convention. No source validates 5 or 6; file-length caps (250 or 400 lines) are unsourced | none | Audits of generated reports | Use a ratchet at 10; don't copy tighter caps |
| Code health and agents | Unhealthy code: at least 30% higher defect risk for AI changes, up to 50% more tokens (the figures conflict between sources) | C | A code-analysis vendor's press release; arXiv 2507.00788 | Vendor-authored; wait for independent replication |
| Duplication, churn | Duplicated blocks and churn rose with AI adoption; refactoring fell | B-/C | GitClear 2025 report (211M lines) | A trend, not proof AI wrote them; the 201,576-commit study shows 90-day rewrites fell from 18% to 12% |
| Delivery | AI raises throughput but still hurts stability; gains need loose coupling and fast feedback | B | DORA 2025 report (about 5,000 respondents) | Survey, correlational |
| Productivity | Experienced developers on mature repos were 19% slower; they expected to be faster | B | METR, arXiv 2507.09089 | 16 developers; early-2025 models |
| Context files | No gain, about 20% more cost; developer-written files slightly better than generated | B | arXiv 2602.11988, 2601.20404 | No replication found |
| Test gaming | Agents edit tests and hard-code outputs; weak tests pass wrong patches (7.8% of "correct" patches failed developer suites) | B | ImpossibleBench; benchmark audits (*secondary*) | Benchmarks, not your repo |
| Coverage | Once suite size is controlled, coverage correlates only weakly with fault-finding | B | Inozemtseva and Holmes, ICSE 2014 (excerpts and a summary read, not the full PDF) | Java, five systems |
| Mutants | Mutant detection tracked real-fault detection; about 73% of 357 real faults were coupled to mutants | B | Just et al., FSE 2014 (excerpts read, *secondary*) | Java; about 17% of faults were not coupled |
| Context engineering | Smallest high-signal context, few tools, load files just in time, notes outside the window | C | Anthropic engineering blog | Guidance, no effect sizes |
| Verification | An independent reviewer rejected 43% of tasks the writer called done (789 tasks, 30 days) | D | A practitioner's forum post | One author, unreplicated |
| Contract fuzzing | In-process schema fuzzing finds 500 errors static checks miss | C | Schemathesis docs and a 16-API benchmark (*secondary*) | Worth a report-only trial |
| Async refactors | No study or tool covers refactoring large async generators | none | Our search, 2026-11-18 | Our protocol for them is practice, not evidence |

## 3. Practices to adopt, in order of benefit per cost

**P1. One gate command** shared by people, hooks, CI and agents: format, lint, types, fast changed-code tests, then
the full tests in CI. Print its runtime. Budget: seconds for pre-commit, minutes for the local gate. (C)

**P2. Characterization (golden) tests before touching legacy code.** Record from the original code in a pristine
checkout, assert the module path, and replay the refactored code at several `PYTHONHASHSEED` values. A golden that
cannot fail proves nothing, so kill mutants against it. (Measured here: eight waves, no behaviour regression
reached main, two defects found and fixed as separate test-first commits.) Full protocol: `docs/REFACTORING.md`.

**P3. Targeted mutation testing.** Mutate only the changed or highest-risk code (auth, parsing, money). Each mutant
pattern must match exactly once; restore by hash. Survivors become tests or documented equivalents. Don't run
whole-repo mutation in CI. (B for fault coupling, *secondary*. This kit does it for its own rules: `make mutate`.)

**P3b. Coverage is a map, mutants are the bar.** Use coverage to find code no test reaches, then judge the evidence
by mutants killed on the lines you changed. Plant a known difference first to prove the comparison can fail. (B)

**P3c. Very large async functions** (agent loops, stream handlers): see the async section of `docs/REFACTORING.md`.
It is our own design, not an established method (research 2026-11-18).

**P4. Neutral commits first, improvements as their own test-first commits.** A change that alters behaviour sits
behind a default-off flag with a flag-off identity test. (Measured here.)

**P5. Determinism.** No real clocks, sleeps or network in unit tests; inject a virtual clock. A flaky test is fixed
or quarantined, never shrugged at. (Measured here: real-clock budget tests failed 14 of 40 runs before a fix and 0
of 40 after; a first-call config race that broke test collection was a real product bug, not test noise.)

**P6. Ratchets.** Complexity (McCabe 10), file length, deferred imports, broad excepts, ticket references.
Baselines only shrink; a raise is listed per file and number in the PR; regenerate once per PR, scope-checked.

**P7. Anti-suppression, soft.** Report blanket `# type: ignore` and `# noqa`, and unused `# noqa` (Ruff PGH003,
PGH004, RUF100), as warnings. Count the current uses before ever making them blocking.

**P8. Independent verification** before "ready": a fresh-context reviewer sees only the diff and the criteria, and
the verdict goes in the PR. Style findings are optional. (`claude/agents/verifier.md`)

**P9. Agent workflow.** Plan, check the spec, write a failing test, implement, verify. One writer per worktree;
subagents for read-only sweeps and reviews; a cheap model for reads and scans, a strong one for decisions; targeted
tests only until the machine is quiet; one heavy suite at a time.

On a shared machine "one heavy suite at a time" needs a mechanism, not a request. Several assistants running tests
at once produced timeouts and false reds. A gate-file chain fixed it: a background script touches `GO-b` when
`DONE-a` appears, then `GO-c` after `DONE-b`. Each assistant does its reading and edits first, waits for its own
GO file before running anything, and writes its DONE file when finished. Reports went from timeouts to clean runs.

**P9b. Script side effects and shell traps.** Two cheap guards, each from a real incident.
- *Importing a script runs it.* A helper script was imported only for its functions; its top-level `main()` ran and
  wrote 13 duplicate tickets to a tracker (deleted within minutes). Every script gets an
  `if __name__ == "__main__":` guard; copy a small helper rather than import a script with side effects; before
  importing one, grep it for a bare top-level call.
- *zsh modifiers mangle refspecs.* In zsh `$VAR:refs/heads/x` applies the `:r` modifier and silently rewrites the
  refspec; the push failed with `src refspec <sha>efs/heads/x does not match any`. Brace the variable:
  `"${VAR}:refs/heads/x"`.

**P10. A scheduled cleanup pass, report only.** A fortnightly read-only audit for duplicate helpers, dead code and
drift from the architecture. (C; the duplication data above gives indirect support.)

**P11. A session-close memory sweep.** Before clearing a long session, list notes that went stale and facts that
were verified; a person chooses what to keep. (Measured here: our own notes drifted, listing merged branches as open.)

**P11b. The tracker is part of done.** One epic per program. Under it, one sub-ticket per finished batch (Done, with
its PR, the evidence and the numbers) and one per planned batch (with its blocker named). A status comment at each
milestone: ready, merged, deployed. Neutral text: no people, and no security findings in a tracker. A merged PR
with a stale ticket is not done.

**P12. Evals for retrieval and prompt changes.** No prompt, chunking or retrieval change without a before/after
score on a fixed set (`examples/evals/README.md`).

## 4. Popular but unproven: do not adopt without evidence

- Tighter complexity caps than your repo can meet (6 per function, fewer than 5 decision points per 100 lines,
  250-line files). No source validates them.
- Hard CI gates for new checks that have no recurring failure behind them.
- A rules-file entry after every mistake; several always-on context files; a directory tree in CLAUDE.md.
- Several subagents editing one tree at once (merge conflicts). Parallelise across worktrees instead.
- Fixed numeric rules from generated reports: a 250-line PR cap, a 5-step circuit breaker, "at most 120 changed
  lines". The audit below found none of them derived from data.
- Routing files by complexity to a named model tier. The supporting study had low power (N=1000, no significant
  difference found, which is not the same as no difference).
- Any recommendation whose only source is a forum thread, a vendor blog about its own product, or a paper with no
  author or ID.

## 5. Soft first: how enforcement grows

1. **Report.** A new check runs in CI or locally, prints findings and exits 0. Count how many it finds today.
2. **Ratchet.** Freeze today's count as a baseline that may only shrink (`bin/ratchet.py`). New code can't add to
   the problem, and old code isn't a blocker.
3. **Block.** Promote to a failing check only when the repo's own history shows the failure recurring (two or more
   times) and the check would have caught it. Record that evidence in the PR that promotes it.

A red CI run costs trust; a missing check costs little until a failure repeats. When a failure does repeat, add a
guard (test, hook, lint), not another reminder.

## 6. Rollout order for a new repo

1. Audit, read only: layout, test count and runtime, the 30 slowest tests, the flaky list, CI jobs and runtimes,
   stale docs.
2. P1, one gate. 3. P5, determinism fixes. 4. P6, ratchets with baselines from today's state. 5. P2 and P3 around
the riskiest modules. 6. P7, P10 and P11 as soft reports. 7. The paired experiment below. 8. Promote a soft check
to blocking only after a repeated failure it would have caught.

## 7. Measuring whether it works

Pick 10 real past tickets and run each with and without the new setup: same model and settings (don't pass a
sampling parameter the model rejects; pin the model id), 3 or more runs each. Record pass rate, steps, tokens, wall
time, human corrections and escaped defects. **Change one intervention per arm**, or you can't attribute the effect;
bundling a context file, two hooks and a verifier into one arm tells you nothing about which helped. Grade with
tests the agent can't edit, outside its environment. Don't use self-reported speed-up. With 10 tasks only large
effects are detectable, so report effect sizes with paired intervals and call the result exploratory. Re-run
quarterly and delete what doesn't earn its place.

## 8. Open questions

- Does lower complexity improve agent success? Only vendor evidence exists.
- What mutation-score target is right? No source gives one; use "all mutants on the changed lines killed or
  triaged".
- Do code-health ratchets beat plain review for AI-written changes?
- Does the 19% slowdown still hold with 2026 models? A follow-up exists but its primary source wasn't found.
- Does coverage.py record branch arcs per dynamic context? The docs don't say; check locally.

## 9. Source quality: read before citing

Five generated deep-research reports fed this page, and an audit of one 1,200-line report found problems worth
knowing about, since they are common: grades inflated by one step (a single preprint labelled A); the same result
attributed to three different arXiv numbers; citations with no authors, ID or venue; thresholds that appear in no
source; and "ready-to-paste" files that used paths and scripts invented for the target repo. It also proposed hard
gates everywhere, against its own stated constraint of soft checks first. The lesson is to trace each number
you'll act on to its primary source, and to label what you only saw in a snippet. Every number above marked
*secondary* needs that check before it goes in a PR or a decision.
