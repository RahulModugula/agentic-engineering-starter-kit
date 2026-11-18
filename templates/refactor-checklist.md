# Refactor checklist (behaviour-neutral)

Protocol and reasons: `docs/REFACTORING.md`. Tick each box with evidence in the PR, not from memory.

## Before touching the code
- [ ] One function, one purpose. No fix mixed in.
- [ ] Golden recorded from the ORIGINAL code in a pristine checkout; the recorder asserted the module path.
- [ ] The recorder fails on a value it can't serialise (it must not record a fake exception).
- [ ] Scenario count: at least 1,000 for a gate or access check; more for an entry point.
- [ ] A planted difference makes the golden fail (the golden can fail).

## The change
- [ ] No change to signatures, order of checks, messages or call order.
- [ ] Anything that does change behaviour is its own commit, test first, behind a default-off flag, with a flag-off
      identity test.

## Proof
- [ ] Golden replayed at three or more hash seeds.
- [ ] Differential in separate processes; normalised fields are an explicit allowlist.
- [ ] At least 12 mutants on the changed code, each pattern matching exactly once.
- [ ] Access checks: ordering mutants and denial-path mutants included.
- [ ] A mutant run was shown to be real: one obvious mutant turns a test red, and the imported module path is the
      mutated tree's.
- [ ] Every survivor is killed or written down as equivalent with a reason, and the claim was tried.
- [ ] Async code: generators closed explicitly; virtual clock; cancellation cases; the comparator caught three
      planted differences.

## Before pushing
- [ ] Ratchet baseline shrank (or every raise is in the PR's table by file and number).
- [ ] Lint, format, hygiene checks.
- [ ] Tests that import the changed code, then the full suite on the exact head.
- [ ] Fresh-context review of the exact diff; verdict in the PR body.
- [ ] Ticket named in the title; commented at ready; closed only when its criteria are met.
