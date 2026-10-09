# Launch plan (personal repo only)

Stars can't be engineered within the rules of the places worth posting. What we control is quality: a repo that
installs safely in minutes, does what it says, and proves it with tests anyone can run. The research behind this
plan, with sources, is in `docs/research/RESEARCH-LAUNCH-2026-10-09.md`.

## Before you make it public

- [ ] **Confirm you own the rights.** This kit was written by you, but an employment agreement can claim work done
      for or on an employer. Check yours. The kit contains no company code or names (`make check` plus the
      name scan in the build prove that).
- [ ] `make verify` is green on your machine (tests, scan over the full history, lint, mutation).
- [ ] The CI workflow is green on Ubuntu and macOS (push to a private repo first).
- [ ] Repository settings:
  - [ ] description: "A tested, safe setup for running parallel Claude Code agents: guard hooks, verified merges,
        human review for core code, and a from-scratch guide";
  - [ ] topics: `claude-code`, `ai-agents`, `developer-tools`, `git-worktrees`, `code-review`, `security`;
  - [ ] social preview image (1280×640).
- [ ] Settings, then Advanced Security: turn on private vulnerability reporting (SECURITY.md relies on it).
- [ ] Protect `main` with a ruleset: require a PR, require the `CI` check, no force pushes, empty bypass list.
- [ ] Turn on Discussions (questions go there, not to Issues).
- [ ] Record the demo GIF (below) and check it plays in the README.
- [ ] Community profile at 100% (Insights, then Community standards).

## Release v0.1.0

```
git tag -s v0.1.0 -m "v0.1.0"          # signed tag; verify with: git tag -v v0.1.0
git archive --format=zip --prefix=agentic-starter-kit/ -o agentic-starter-kit-v0.1.0.zip v0.1.0
shasum -a 256 agentic-starter-kit-v0.1.0.zip > SHA256SUMS
gh release create v0.1.0 agentic-starter-kit-v0.1.0.zip SHA256SUMS --notes-file CHANGELOG.md
```
Build the archive twice and compare the SHA-256 sums before calling it reproducible. Prefer an immutable release.

## The demo (vhs)

```
brew install vhs
vhs demo/demo.tape     # writes demo/demo.gif
```
`demo/demo.tape` shows: the dry run, the install, the guard blocking a push to main, and the rollback. It never
records a real token or account name.

## Posting

**Show HN** (rules: something people can try, non-trivial, made by you, no sign-up gate; never ask for upvotes):

> **Show HN: Agentic Starter Kit – guard hooks, verified merges and human review for parallel Claude Code**
>
> I run several Claude Code sessions in parallel and kept hitting the same failures: a session pushing
> straight to main, a watcher that silently never fired, credentials expiring mid-run, core code merging on AI
> review alone. This kit is the setup I ended up with:
> - deterministic guard hooks;
> - a merge queue that merges only a verified commit;
> - review tiers that flag core code to a person;
> - a secret scanner;
> - an installer with dry run and exact rollback.
>
> Every safety rule has a test, and a mutation harness proves each test fails when the rule is removed. Everything
> runs offline, with no model calls. What it doesn't do: stop a hostile process on your own machine. The threat
> model is in ARCHITECTURE.md. I'd value feedback on the safety model in particular.

Post when you can stay in the thread for the next 4–6 hours. Answer every question; fix what people find.

**Elsewhere:** post only where tools like this are explicitly on-topic, after reading that community's
self-promotion rules. One focal link: the repo.

## The first week

- Reply to every issue within a day, even if it's only "reproduced, looking".
- Label issues (`bug`, `question`, `good first issue`) and move questions to Discussions.
- Ship 0.1.1 with the fixes, and credit reporters in the CHANGELOG.
- If people keep asking the same question, the README is missing that answer: fix the README.
