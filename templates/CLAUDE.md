# <Repo> orientation

<!--
Keep this under 60 lines. Commands and non-obvious rules only. No layout tree, no copy of the README.
Why: repository context files gave no success gain and over 20% extra cost in one study (arXiv 2602.11988; a single,
unreplicated study, so a reason to stay small, not a proven law). Delete this comment in your copy.
A rule earns a line only if breaking it has already cost you something. Fix repeated mistakes with a test or a
hook, not another line here.
-->

One paragraph: what this is and what it ships.

## Commands (exact)

- Setup: `<cmd>`
- Fast check (changed code): `<cmd>`
- Full tests: `<cmd>`
- Lint and format: `<cmd>`

## Rules that are not obvious (each one bit us)

- <rule>: <why, in one clause>
- <rule>: <why, in one clause>

## Where to change what

- <stage or concern> goes in <file>; tests patch these names, so keep them.

## Before pushing

Run lint and the full tests from the worktree you changed. The PR names its ticket and lists any ratchet raise.

## Tests

Tests verify correctness; they don't define the solution. Don't hard-code for test inputs. If a test is wrong or the
task can't be done, stop and say so instead of editing the test.
