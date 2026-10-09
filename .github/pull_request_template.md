## What and why
<!-- One or two sentences. Link the issue: Fixes #123 -->

## How it was verified
<!-- The commands you ran and what they printed. -->
- [ ] `make check` passes locally
- [ ] `make mutate` passes (if you changed a guard, gate, scanner or the installer)
- [ ] Ran `./install.sh` (dry run) and `--rollback` in a throwaway HOME (if the installer changed)

## Risk
- [ ] Touches a core path (installer, hooks, merge queue, review tiers, scanner): needs maintainer review
- [ ] CHANGELOG.md updated under Unreleased
- [ ] Docs updated, if behaviour changed
