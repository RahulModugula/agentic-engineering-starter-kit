# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-09
### Added
- Guard hook: no pushes to main, no force pushes, merges only from the coordinator, no pattern kills,
  owner-only human approvals.
- Stop hooks: a turn can't end while the project's checks fail, or with announced-but-unstarted work.
- Merge queue with exact-sha guard, verifier gate, human-review tiers and an optional green-main mode.
- Review tiers: `.review-tiers` policy, escalation for weakened tests and core code moved or imported into
  agent-only paths, CODEOWNERS generator, human queue and spot-check sampling.
- Ops helpers: outcome watchers, PID-reuse-safe liveness, SSO preflight, retry with backoff, bound approvals.
- Secret/PII scanner over the working tree and full history; pre-commit hook.
- Installer with dry run, backup, exact rollback and drift check.
- Tests for every rule, an offline end-to-end test, and a mutation harness that proves each test can fail.
- Docs: start-from-scratch guide, architecture and threat model, review tiers, testing, research notes.
