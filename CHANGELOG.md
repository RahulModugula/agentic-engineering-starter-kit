# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]
### Added
- Codex CLI, OpenCode and Antigravity CLI support: `install.sh --tool` (default: each one on PATH) merges the kit's
  hooks into each tool's hook file, or links the OpenCode plugin, and gives each tool the kit's rules in its global
  `AGENTS.md`. All of it is in the backup and undone by `--rollback`; `--status` checks it.
- `agent-adapter.sh`: runs the unchanged guards on each tool's hook input; "ask" becomes "deny"; fails closed.
- `file-guard.sh`: the kit's `Read(...)`/`Edit(...)` deny rules for tools without Claude Code's permission rules.
- `LANE_TOOL` in `lanes.zsh`: `coord` and `lane` on another agent CLI, each lane in its own worktree.
- `docs/OTHER-AGENTS.md`: what each tool enforces, free options, and a warning about free models and confidential data.
### Changed
- The guards now also protect the other tools' hook configs and rules (`~/.codex`, `~/.config/opencode`, `~/.gemini`)
  and Codex's and OpenCode's credential files. Protected folders count when named with `//`, `/./` or `..`, with a
  wildcard in a dot-folder's name under your home (`~/.cod*`), and when a command runs inside them (`cd`, or a
  tool's working-directory argument).
- `find` counts as changing files only with `-delete`, `-exec`, `-ok` or `-fprint*`, so a read-only `find` in a
  protected folder is allowed.
### Fixed
- lane-guard: a wildcard anywhere under `~/.claude` (`rm ~/.claude/hook*/lane-guard.sh`) got past the controls
  check. It also ignored case, which on the default macOS disk doesn't matter (`~/.CLAUDE` is `~/.claude`).
- `tests/linux-in-docker.sh` exited 0 when a step failed: each step pipes into `tail`, and there was no `pipefail`.

## [0.1.0] - 2026-10-09
### Added
- Guard hook: no pushes to main (including HEAD, glob, matching and config-redirected pushes), no force pushes,
  merges only from the coordinator (CLI, API and plain HTTP), no pattern kills, no edits to the guard's own
  controls, owner-only human approvals and test locks; prod AWS writes ask. Fails closed.
- Stop hooks: a turn can't end while the project's checks fail (three tries, then you're told), or with
  announced-but-unstarted work.
- Merge queue with exact-sha guard, verifier gate, human-review tiers and an optional green-main mode.
- Review tiers: `.review-tiers` policy, escalation for weakened tests and core code moved into agent-only paths,
  CODEOWNERS generator, human queue and spot-check sampling.
- Ops helpers: outcome watchers, PID-reuse-safe liveness, SSO preflight, retry with backoff, bound approvals.
- Secret and personal-data scanner over the working tree, full history and commit metadata; pre-commit hook.
- Installer that merges into existing settings, with dry run, backup, exact rollback and a drift check.
- Tests for every rule, an offline end-to-end test, and a mutation check that proves each test can fail.
- Docs: start-from-scratch guide, leaders' guide with costs and a pilot plan, architecture and threat model,
  review tiers, testing, research notes with dated sources.
