# Refactoring without changing behaviour

A protocol for splitting large functions (or moving code) when agents do the typing and nothing user-visible may
change. It is practice, built on the evidence in `docs/PRACTICES.md`: passing the existing tests is weak proof of
equivalence (about one in five non-equivalent LLM refactorings passed them, arXiv 2602.15761, B, *secondary*), so
the protocol records behaviour first and then tries to break the result. Dates: research read 2026-11-18. The
steps are Python-flavoured; the ideas are not.

Measured in one production codebase (about 38,500 tests, eight waves): no behaviour regression reached main, two
real defects were found by the goldens and fixed as separate test-first commits, and a complexity baseline shrank
from 297 entries to 36 with no loosening. That is one codebase and no control arm; treat it as a case, not a rate.

## The protocol

1. **Pick one function over the limit.** One at a time; don't mix a refactor with a fix.
2. **Record a golden from the ORIGINAL code, in a pristine checkout.** Drive the function through scenarios (at
   least 1,000 for a gate or access check, more for an entry point) and store inputs and outputs, including the
   exceptions and the order of calls it makes. The recorder asserts the module path it imported (`mod.__file__`
   starts with the pristine checkout), so a golden can't be silently recorded from the code you are about to change.
3. **Split into named helpers.** No change to a signature, the order of checks, a message or the order of calls.
   Behaviour-visible improvements are separate commits, test first, behind a default-off flag with a flag-off
   identity test.
4. **Replay the golden on the new code at three or more `PYTHONHASHSEED` values.** Set iteration and dict-of-set
   order is the commonest hidden dependence.
5. **Run a differential in separate processes.** Original and refactored code each run in their own process on the
   same inputs (so module state and caches can't leak between them) and the outputs are compared. Normalise only an
   explicit allowlist of fields that are legitimately nondeterministic (ids, timestamps, durations). An allowlist
   shows new fields; a denylist hides them.
6. **Kill mutants on the changed code.** At least 12 per function: flip a comparison, drop a branch, swap two
   statements. For any access or permission check add **ordering mutants** (move the check after the action it
   guards, swap two checks) and **denial-path mutants** (return allow where it denied). Every mutant must be killed,
   or written down as equivalent with the reason.
7. **Shrink the ratchet.** Delete the function's baseline entry (`bin/ratchet.py shrink`), run lint and the
   hygiene checks, run the tests that import what you changed.
8. **Independent review on the exact diff.** A fresh-context reviewer (`claude/agents/verifier.md`) sees the diff
   and the criteria, not your reasoning, and tries to make the goldens fail.
9. **Full suite on the exact head before any push.** One merge commit per area. A new push means a new run.

`templates/refactor-checklist.md` is this list as a checklist; `templates/pr-body.md` is where the evidence goes.

## Pitfalls we hit

Each of these produced a result that looked fine and was not.

- **Mutants applied to a copy silently passed.** A test harness that puts the worktree's `src` first on
  `sys.path` imports the worktree's unmutated code, not the mutated copy, so the tests ran against the original
  and the run looked green whatever the mutant did. Before trusting a mutant run, plant one obvious mutant and confirm a test fails, and print
  the imported module's path inside the mutated tree. Set `PYTHONDONTWRITEBYTECODE=1` and clear `__pycache__` so a
  stale `.pyc` can't mask a change.
- **A golden recorder that can't serialise a value records a fake exception.** If a result isn't JSON-able and the
  recorder's `except` turns that into "raised TypeError", the golden asserts an error that never happened in the
  original. Make the recorder fail loudly on an unserialisable value; encode the value explicitly (type name plus a
  stable representation) instead.
- **"Equivalent mutant" is a claim, not a finding.** Survivors in refactored code are often truly equivalent, which
  is undecidable in general (Papadakis et al., 2018 survey, C), so someone has to triage. Check each claim by
  trying to write an input that tells the two apart. If you can, it was a test gap.
- **A mutant pattern must match once.** A substitution that hits the first of several matches may mutate the wrong
  line; `grep -c` the pattern and require exactly 1 before you call a mutant survived. `tests/mutate.py` in this
  kit reports zero matches as STALE and several as AMBIGUOUS for the same reason.
- **Don't probe a tree a mutant run is editing.** Run exploratory checks against a separate copy.
- **Real-clock bounds flake under load.** A test that asserts "finished within 200 ms" fails when the machine is
  busy, with no bug behind it (measured: 14 of 40 runs failed before the fix, 0 of 40 after). Use CPU time rather
  than wall time, event handshakes instead of sleeps, and fake clocks and locks. Never weaken the assertion; fix
  the shape. A test-only fix goes in its own commit.
- **A byte-identical flag-off test must drop fields that vary** (timings, ids), or it flakes.
- **Registries that accumulate.** A function that registers into a module-level dict without clearing it makes the
  second test see the first test's entries. Clear and restore in the test.

## Large async functions (agent loops, stream handlers)

We found no published tool or study for refactoring async generators (research 2026-11-18), so this is our design.
Treat each item as an experiment you have to prove can fail.

- **Measure reach per scenario.** Run the scenarios under coverage.py with `dynamic_context = "test_function"` (or
  scenario ids), branch mode on. List the branch arcs inside the code you will move that no scenario reaches. The
  docs don't say whether contexts record arcs; verify locally and fall back to line contexts plus a separate arc
  check.
- **Make the dimensions explicit rather than fuzzed:** config flags, history length, tool results, stream errors,
  retry exhaustion, timeouts and cancellation at each await. A scripted scenario per unreached arc is cheaper and
  easier to audit than a coverage-guided fuzzer, for which we found no async evidence. Stateful property testing
  (Hypothesis rule-based machines) may help for interleavings; we haven't shown it drives an async generator.
- **Virtual clock, separate processes.** Run original and refactored code in separate processes on a virtual clock.
  Each `await` is a cancellation point and `asyncio.timeout()` turns cancellation into `TimeoutError`, so moving an
  `await` in or out of a `try`/`finally` or a timeout block changes behaviour the event trace will show.
- **Close generators explicitly.** Drive them with `contextlib.aclosing` and assert the trace, including the
  finalisation events. A generator abandoned mid-stream is closed by the garbage collector on a later loop tick, so
  its `finally` events can land at a different point in the trace (PEP 525).
- **Inject cancellation at the k-th suspension** (a proposal, no external validation): wrap each awaitable in a shim
  with a counter, cancel at k = 1..N, and compare original and refactored traces, also with `aclose()` at each k.
- **Prove the comparator can fail.** Plant at least three known differences (swap two awaits, move a `finally`, drop
  a retry) and require the differential to report each. Record the result in the PR.
- **Move code only when the moved lines are reached and their mutants die.** Aim for "no function over about 200
  lines", not one giant state object that lowers the metric without lowering what a reader has to hold.

## What this does not prove

Goldens show equivalence on the scenarios you recorded; they say nothing about inputs nobody thought of. Mutants
show the tests notice the changes you tried. The differential compares what the harness observes: side effects it
doesn't see are not compared. Say which of these applies in the PR (`templates/pr-body.md`, "What is not proven").
