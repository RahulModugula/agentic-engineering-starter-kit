<!-- PR body for a change that needs evidence (refactors, fixes, anything behaviour-sensitive).
     Neutral text: no people, no internal names, no security findings. Every number has a date and an n. -->

## What and why
<One or two sentences. The ticket is in the title.>

## Commit map
| Commit | What it does | Behaviour change? |
|---|---|---|
| <short sha> | <one line> | none / flagged off by default / yes: <what> |

## Evidence
Commands run on the exact head `<short sha>`, with what they printed. Dates and counts, not adjectives.
- `<command>` -> `<result line>` (<date>)
- Goldens: recorded from the original at `<sha>` in a pristine checkout (module path asserted); <n> scenarios;
  replayed at hash seeds <list>.
- Differential (separate processes): <n> inputs, <n> differences.
- Mutants on the changed code: <n> run, <n> killed, <n> equivalent (reason for each below).
- Check that can fail: <the planted difference or mutant, and the test that went red>.

## Behaviour differences
<None, or each difference stated plainly: what changed, who sees it, the flag that gates it.>

## Ratchet raises
| File or key | Baseline before | After | Why it had to rise |
|---|---|---|---|
| none | | | |

## What is not proven
<Inputs not covered by the scenarios, side effects the harness doesn't compare, tests not run and why.>

## Review
Independent reviewer (fresh context, saw only the diff and criteria): <PASS / numbered findings> at `<full sha>`.
Findings fixed: <list, or none>.
