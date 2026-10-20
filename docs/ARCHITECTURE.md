# Architecture

How the setup works, what each part enforces, what it does not, and how each claim is tested. Written for people
who will audit it. For a guided start, read `START-FROM-SCRATCH.md` instead.

## The model in one paragraph

One human, many AI sessions. A **coordinator** session plans and merges; **lanes** each do one task in their own
git worktree; a **verifier** reviews every pull request with a fresh context. Rules that must hold are enforced by
**deterministic hooks and scripts**, not by instructions to the model, because instructions are advisory and hooks
are not. Every enforcement point has a test that proves it fires and a mutation check that proves the test fails
when the rule is removed. The human keeps three things: approving risky actions in the pane that asks, reviewing
**core** code (review tiers), and deciding what to build.

```
            you ── approve in-pane ──┐                ┌── human-approve.sh (core code, exact sha)
                                     ▼                ▼
  coordinator ──brief──▶ lane-1 ──PR──▶ verifier ──VERIFIED <sha>──▶ merge-queue ──▶ main
      │                  lane-2 ──PR──┘                   │              │
      │                                                   │              ├─ merge-guard: head == sha, checks green,
      └── human-queue.sh: "these PRs need you, read these files"         │  mergeable, not draft/unstable
                                                                         ├─ review tier: human tier waits for a person
                                                                         └─ green mode (opt-in): main CI green first,
                                                                            CI re-checked on the new head
```

## Components and what they enforce

| Component | Enforces | Born from (the failure it prevents) | Tested in |
|---|---|---|---|
| `claude/hooks/lane-guard.sh` (PreToolUse, Bash) | No push that could update main/master (named, `HEAD`/`@`, glob and matching refspecs, `--all`/`--mirror`, push settings via `git -c`/`git config`), no force push, no merge outside the coordinator's checkout (`gh pr merge`, the API, plain HTTP, merge scripts), no `pkill`/`killall`, no variable as a command name, no file-changing command aimed at the guard's own controls (hooks, settings, trust list, approvals, test lock), human-review approvals are owner-only, prod-profile AWS calls other than reads ask. It fails closed: no `jq` or unreadable input blocks the command, and on Claude Code 2.1.295+ the installer sets `onFailure: "block"` so a guard that times out or can't start blocks too (before that, Claude Code lets the command run) | Direct pushes to main; a pattern kill that took down five unrelated jobs; approvals relayed between sessions | `tests/test_guardhook.sh` (incl. look-alikes that must be allowed and every bypass found in review), `tests/test_e2e.sh` |
| `claude/hooks/verify-before-done.sh` (Stop) | In a repo you've trusted (`bin/trust-repo.sh`), a turn can't end while the project's checks fail on changed files; after three blocks on the same state it lets the turn end and tells you, so a stuck session can't loop; an untrusted repo's check code never runs | "Done" claimed on a red suite | `tests/test_e2e.sh` |
| `claude/hooks/tests-lock.sh` (PreToolUse, Edit/Write) | While `.claude/tests-locked` exists, test files are read-only to sessions; only the owner locks or unlocks | Tests edited to get green | `tests/test_tests_lock.sh` |
| `claude/hooks/lane-stop-guard.sh` (Stop) | No "next I'll…" endings while the lane's state file has open items; no test-only branches | Sessions that announced work and stopped; tests weakened to get green | `tests/test_e2e.sh` |
| `claude/hooks/lane-state.sh` (SessionStart compact/resume) | Re-injects the lane's state file after compaction | Context lost at compaction | `tests/test_e2e.sh` |
| `claude/hooks/notify.sh` (Notification) | A desktop notice when a session waits on you | Panes waiting unseen for an approval | `tests/test_hooks_misc.sh` |
| `claude/hooks/audit-log.sh` (PostToolUse, Bash, async) | A private (0600) JSONL record of every shell command each session ran, with common secret formats masked | Not being able to say afterwards what an agent actually did | `tests/test_hooks_misc.sh` |
| `claude/hooks/denied-log.sh` (PermissionDenied) | Logs every auto-mode classifier denial, so repeat blocks get fixed once | The same block re-asked in many panes | `tests/test_hooks_misc.sh` |
| `claude/hooks/agent-adapter.sh`, `file-guard.sh`, `tools/` (Codex, OpenCode, Antigravity) | The guards above, unchanged, on each tool's own hook input: shell commands to lane-guard, every edited file (each file in a patch too) to the test lock and file guard, reads to the file guard; "ask" becomes "deny"; Antigravity's Stop runs verify-before-done. The file guard applies your settings' `Read(...)`/`Edit(...)` deny rules (symlinks checked by target). Both fail closed | The same guards being Claude-only, when the cheapest way in for many people is another tool | `tests/test_adapters.sh`, `tests/test_install_tools.sh`, `tests/test_lanes.sh` |
| `claude/lib/opslib.sh` | Outcome watchers (marker/log, not process names), PID-reuse-safe liveness, SSO preflight, auth errors stop runs, retries with backoff | A `pgrep -f` watcher that never fired; runs dying mid-way when credentials expired; one network blip killing a long run | `tests/test_opslib.sh` |
| `bin/merge-guard.sh` | Merge only at the exact sha, every check completed and green (≥ N), mergeable, not draft/unstable; reads back MERGED | Merging a stale head; merging past a pending check | `tests/test_merge_tools.sh` |
| `bin/merge-queue.sh` | Merges the queue file in order; needs the verifier's `VERIFIED <sha>` **and** the coordinator's record of it; human tier waits; window or green mode | A builder posting its own VERIFIED (sessions share one GitHub account); green PRs turning main red together | `tests/test_merge_tools.sh` |
| `bin/review_tier.py` + `.review-tiers` | Core paths, renamed-out core code, policy edits, deleted/weakened/skipped tests, agent files importing core code, unreadable or truncated diffs → **human** | Core logic merging on AI review alone | `tests/test_review_tier.sh` |
| `bin/human-queue.sh` / `human-approve.sh` / `human-sample.sh` | What waits on you; your approval per sha; weekly spot-checks of agent-only merges | Flags nobody sees | `tests/test_merge_tools.sh`, `tests/test_guardhook.sh` |
| `bin/go.sh` + `require_go` (opt-in) | A go is bound to the script's bytes, args, listed env and sources, single use, expiring | Approvals that depended on which pane you typed in; scripts edited after approval | `tests/test_gos.sh` |
| `bin/scan.sh` | Catches common secret formats (two dozen rules, plus gitleaks if installed), personal emails and session state in the tree, **the history and commit metadata** | Leaking a token or transcript when sharing a repo | `tests/test_scan.sh` |
| `install.sh` | Dry run by default; backup; links program files; **merges** into your settings and adds one import line to your CLAUDE.md (removes nothing of yours); exact rollback; drift check; refuses a `settings.json` it can't parse | Breaking a working setup with no way back | `tests/test_install.sh`, `tests/test_e2e.sh` |
| `bin/measure.py` | Before/after numbers: credential-killed runs, merge wait p50/p90, overnight stall minutes | Improvements claimed without numbers | `tests/test_measure.sh` |

## How it's verified

- `make check`: every test plus the secret/PII scan over the full git history.
- `make mutate`: `tests/mutate.py` applies each mutant in `tests/mutants.txt` (one broken rule each) to a scratch
  copy and requires the matching test file to fail. A surviving mutant is a test gap; a mutant whose target text
  has gone is reported as stale, never skipped silently.
- `make verify`: check + mutate + lint. Run it before any release.
- Tests never call a model or the network: hooks are driven with the same JSON Claude Code sends on stdin, GitHub
  through a fake `gh`, AWS through a fake config and token cache, and the installer in a throwaway `$HOME`.

## Threat model and limits

- **What it stops:** mistakes, drift, and laundering, where one session gets another to do what it may not. It
  stops pushes to main, merges outside the coordinator, pattern kills, unreviewed core code, secrets in shared
  repos, and runs started on dying credentials.
- **What it doesn't:** a deliberately hostile local process. Every session runs as the same OS user and could
  edit the guards. The server-side controls (branch rulesets, code-owner review from a separate human account)
  are the stronger layer where your GitHub plan allows them; `docs/REVIEW-TIERS.md` says how.
- **Hooks vs the model:** a PreToolUse deny holds in every permission mode, including auto and bypass, so the
  guard is the fixed layer around auto mode's classifier. Allow rules resolve before the classifier: never write
  a path-only allow rule for a script any session can edit.
- **Your `!` lines** (`! human-approve.sh …`) are your own input, not a tool call. The docs describe shell mode
  as running "without going through Claude"; check it once on your machine:
  `! killall -s zz-no-such-proc` should run, while asking Claude to run the same command should be denied.
- **The coordinator check trusts the session's working directory.** A lane started in the coordinator's checkout
  could merge from there (a `cd` inside a command is caught for pushes; the guard reads the hook's directory). This is the same-user limit again; the merge queue's exact-sha, VERIFIED and
  human-tier gates still apply, and GitHub's server-side rules are the hard boundary.
- **The guard parses shell, it doesn't execute it.** It sees through wrappers, shell keywords, `xargs`, heredocs fed
  to an interpreter, and `git`/`gh` global flags (every bypass found in review is a test case), but a program that
  writes files itself, such as a Python script, isn't a Bash command it can see. The review tier and the scanner
  are the backstops for that.

- **Supply chain: you are trusting this repo.** Installing it makes its hooks run before every command you or a
  session runs. Read `install.sh --dry-run` output and the hooks before applying, pin to a commit or tag you
  reviewed, and treat changes to `claude/hooks/` like changes to production code (they're `human` tier in this
  repo's own `.review-tiers`). The kit's settings deny Claude edits to the installed hooks, settings and trust
  list, and the guard blocks shell commands that would change them.
- **Prompt injection.** A web page, issue, file or tool output can contain text written to steer the model. The
  kit's `CLAUDE.md` tells sessions to treat such content as data, which helps but is advisory. What holds
  regardless is deterministic: the guard's denies, the merge gates, human review of core code, and approvals
  that only a person can type. Don't grant broad allow rules or connect tools that can act on your behalf (email,
  payments, production) to sessions that read untrusted content.

- **A repo can't switch the guards off.** A project's `.claude/settings.json` can set `disableAllHooks`; the session
  commands pass `"disableAllHooks": false` through `--settings`, which outranks project settings. Auto mode's
  classifier gets the same rules in plain words (`autoMode.hard_deny`, read only from your user settings), and
  destructive git commands (`reset --hard`, `clean -f`, `branch -D`, `stash drop`…) always ask.
- **Other agent CLIs are weaker here.** Codex, OpenCode and Antigravity have their own project-level config, which
  the lane commands can't override the way `--settings` does for Claude Code. They have no "ask" a hook can give,
  and OpenCode has no stop hook that can keep the agent working. The adapter is tested against each tool's
  documented hook format, not the live CLIs. `docs/OTHER-AGENTS.md` has the per-tool table and a one-minute live check.
- **"Yes, and don't ask again" is shared.** Choosing it inside a lane saves the rule to the main checkout's
  `.claude/settings.local.json`, so every lane and the coordinator get it. Say yes once rather than "always" for
  anything you wouldn't approve in every session.
- **Rule of two.** Keep any one session from having all three of: reading untrusted content (web, issues), access
  to secrets or production, and the ability to push or reach the outside world. The researcher agent is read-only
  for this reason; give a lane that does research no prod profile.
- **Optional second layer: the OS sandbox.** Claude Code's sandbox (`sandbox.enabled`) confines what Bash commands
  can write and reach at the OS level, which covers what the guard can't see (a script that writes files itself).
  It can break tools that need the network or Docker, so try it on one lane first; it isn't on by default here.
  Sources: code.claude.com/docs/en/hooks, /sandboxing, /worktrees, /auto-mode-config (read 2026-10-09).

## Design decisions

The research behind each choice is in `docs/research/`, with sources and the date they were read. In short:
- **Hooks over prompts:** the docs call hooks deterministic and CLAUDE.md advisory.
- **Outcome watchers:** macOS `pgrep` skips itself and its ancestors, so a pattern can only match a sibling,
  which is exactly the bug.
- **No batch-branch landing:** pushing a batch to main marks every PR in it merged, past its own checks.
- **The review policy is read from the base branch:** a PR can't loosen its own rules.
- **Fail closed** everywhere a reading is missing: an unreadable diff, a truncated file list, an unknown policy,
  a missing sign-in record, a missing CI run.
