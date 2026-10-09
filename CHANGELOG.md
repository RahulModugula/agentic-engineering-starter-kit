# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
