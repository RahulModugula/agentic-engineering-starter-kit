## What and why
<!-- One or two sentences. Link the issue: Fixes #123 -->

## How it was verified
<!-- The commands you ran and what they printed. -->
- [ ] `make check` passes locally
- [ ] `make mutate` passes (if you changed a guard, gate, scanner or the installer)
- [ ] Ran `./install.sh` (dry run) and `--rollback` in a throwaway HOME (if the installer changed)

Numbers carry a date and a count (for example "18 passed, 0 failed, 2026-11-18"). For a refactor or a
behaviour-sensitive change, `templates/pr-body.md` has the longer form.

## Behaviour differences and what is not proven
<!-- State each behaviour change plainly, or "none". Then what your checks do not cover. -->

## Risk
- [ ] Touches a core path (installer, hooks, merge queue, review tiers, scanner): needs maintainer review
- [ ] CHANGELOG.md updated under Unreleased
- [ ] Docs updated, if behaviour changed
