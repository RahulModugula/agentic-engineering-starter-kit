# Contributing

Thanks for helping. Bug reports, docs fixes and new guards are all welcome.

1. For anything bigger than a typo, open an issue first so we can agree on the approach.
2. Fork the repo and branch from `main`.
3. Run `make check` before pushing; CI runs the same target on Ubuntu and macOS. For changes to a guard, gate or
   the installer, also run `make mutate`.
4. **Every safety rule needs a test that fails without it.** Add the test, and add a line to `tests/mutants.txt`
   that removes your rule; `make mutate` must show it killed.
5. Add a line under `## [Unreleased]` in `CHANGELOG.md`.
6. Open a PR and fill in the template.

**Editing the kit with Claude Code:** the installed settings deny Claude edits to `~/.claude/kit/**`, which links
to your clone, and deny rules follow links. While you work on the kit, remove `"Edit(~/.claude/kit/**)"` from
`~/.claude/settings.json`; put it back after (`./install.sh --status` reports it missing until you do).

Questions go to Discussions, not Issues. Be kind: see `CODE_OF_CONDUCT.md`. By contributing, you agree your work
is licensed under this project's MIT license.
