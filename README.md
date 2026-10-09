# Agentic Starter Kit

**A tested, safe setup for running parallel Claude Code agents.** One person stays in charge while agents plan,
build, test, review and merge. The rules that must hold are enforced by hooks and scripts, not by asking the model
nicely. Core code is flagged to you before it merges. Every safety rule ships with a test, and a mutation check
proves each test fails when the rule is removed.

[![CI](https://github.com/RahulModugula/agentic-starter-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/RahulModugula/agentic-starter-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<!-- Demo GIF: record with `vhs demo/demo.tape` (see docs/LAUNCH.md), then add: ![demo](demo/demo.gif) -->

```
you ─┬─ coord ──brief──▶ lane-1 ─┐
     │                   lane-2 ─┼─PR─▶ verifier ──VERIFIED <sha>──▶ merge queue ──▶ main
     │                   lane-3 ─┘                                      │
     └──────── human-queue: "these PRs touch core code; read these files" ◀┘
```

## Who it's for

| You are… | Start with |
|---|---|
| Brand new: never used a terminal | [`START-FROM-SCRATCH.md`](START-FROM-SCRATCH.md): every step, every command, what to do when it goes wrong |
| A CTO, CEO or engineering leader | [`docs/FOR-LEADERS.md`](docs/FOR-LEADERS.md): value, controls, costs, risks, rollout and what to measure |
| An engineer evaluating it | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): components, what each enforces, threat model, and how each claim is tested |
| Deciding what agents may ship alone | [`docs/REVIEW-TIERS.md`](docs/REVIEW-TIERS.md) |
| Making agent-written code trustworthy | [`docs/TESTING.md`](docs/TESTING.md) |

## Quickstart

Needs Claude Code (Pro plan or higher), git, `gh`, `jq` and zsh; macOS or Linux (on Windows, use WSL).

```
git clone https://github.com/RahulModugula/agentic-starter-kit.git ~/agentic-starter-kit
cd ~/agentic-starter-kit
make check               # run every test first: it all passes, offline, in about a minute
./install.sh             # dry run: every file it would add or change, with a diff
./install.sh --apply     # backs up ~/.claude, then installs; undo with ./install.sh --rollback
echo 'source ~/.claude/lanes.zsh' >> ~/.zshrc
```
Set `REPOS=(…)` and `MAIN_REPO=…` in `~/.claude/lanes.zsh`, then run `coord`, `lane 1`, and `lane verifier`.

## Why it's different

- **Deterministic, not advisory.** The kit's hard rules are hooks: a PreToolUse deny holds in every permission
  mode, including auto. Instructions in a CLAUDE.md are advice; hooks are enforcement, within the limits stated in the threat model.
- **Proven, not claimed.** Over 340 test cases, each showing a rule fires and look-alikes pass. An offline
  end-to-end test installs into a throwaway home and drives every hook as Claude Code would. `make mutate` breaks
  every rule on purpose; all 72 mutants are killed.
- **Humans where it matters.** Agents ship UI, tests and benchmarks alone. Core code waits for a person at the
  exact commit, and moving core code out of a core folder doesn't dodge that.
- **Built from real failures.** Each guard exists because something went wrong in daily use: a watcher that never
  fired, credentials dying mid-run, pattern kills taking down other jobs, green PRs turning main red together.
  `docs/ARCHITECTURE.md` maps each guard to its failure.
- **Honest limits.** The local guards stop mistakes and keep approvals from being passed between sessions, not a
  hostile process on your own machine. The docs say exactly where server-side rules take over.

## What's inside

| Part | What it does |
|---|---|
| `claude/hooks/lane-guard.sh` | Blocks pushes to main, force pushes, merges outside the coordinator, `pkill`/`killall`, and sessions approving core code themselves |
| `claude/hooks/verify-before-done.sh`, `lane-stop-guard.sh` | A turn can't end while your project's checks fail, or right after announcing work it didn't start |
| `claude/hooks/notify.sh`, `denied-log.sh`, `lane-state.sh`, `statusline.sh` | A desktop notice when a pane waits on you; a denial log; state re-injected after compaction; context and plan usage at a glance |
| `claude/lib/opslib.sh` | For long jobs: wait for outcomes (not process names), PID-safe liveness, an SSO preflight, retry with backoff |
| `bin/merge-queue.sh`, `merge-guard.sh` | Merge only the exact verified sha with every check green; optional "main must be green" mode |
| `bin/review_tier.py` + `.review-tiers` | Flags core code, moved core code, policy edits and weakened tests for a person |
| `bin/human-queue.sh`, `human-approve.sh`, `human-sample.sh` | Your review queue, your per-sha approval, weekly spot-checks |
| `bin/scan.sh` | Blocks secrets, personal data and session state in the tree and the full history |
| `bin/measure.py` | Before/after numbers: credential-killed runs, merge-wait p50/p90, overnight stalls |

## FAQ

**Does it phone home or need an API key?** No. It's shell scripts and Python with no dependencies beyond `git`,
`gh` and `jq`. Claude Code uses your own login.

**Will it break my existing setup?** `./install.sh` is a dry run. `--apply` backs up every file it replaces, and
`--rollback` restores them byte for byte (that's tested).

**Can I use parts of it?** Yes. Every script stands alone, and the hooks are plain files you can copy.

**Why not GitHub's merge queue?** It isn't available for private repos on personal accounts, or for private org
repos without Enterprise Cloud. The kit's queue works everywhere `gh` does.

## About the author

Built and maintained in the open (author: Rahul Modugula). The practices here distil nine years of hands-on
software engineering, and were refined through review with technology and business leaders, product managers, and
engineers from senior staff to new hires. It is the setup used every day to run parallel AI agents on production work.

## Contributing and security

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Every safety change needs a test that fails without it. Report
vulnerabilities privately: [`SECURITY.md`](SECURITY.md). MIT licensed.
