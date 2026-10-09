# Review tiers: what agents ship alone, and what a person must read

The agent pipeline builds, tests, verifies and merges everything. Every change also gets a **tier**:

| Tier | What it covers | Who must approve before merge |
|---|---|---|
| **agent** | Paths your policy lists as `agent`: typically UI/UX, tests, benchmarks, docs | the AI verifier (`VERIFIED <sha>`) |
| **human** | Core code: auth and permissions, data access and privacy filters, money and cost paths, infrastructure, schemas and migrations, release and deploy scripts, the review rules themselves, **and any path the policy doesn't list** | the AI verifier **and a person**, at that exact sha |

Agents still do all the work on human-tier changes. The difference is that the change is **flagged to you**, names
the files to read, and **can't merge** until a person has reviewed it. The installer links `~/.claude/kit` to the folder
you cloned, so the commands below work wherever that is.

## The policy file

Put a `.review-tiers` file at your repo's root. `examples/review-tiers/generic.review-tiers` is a starting point:

```
default human                       # anything not listed needs a person (fail closed)
agent  web/src/**                   # UI: agents end to end
agent  tests/**                     # tests
human  src/auth/**                  # human lines win over agent lines, whatever the order
escalate (import|from).*\b(auth|db|secrets?|iam)\b   # an agent-tier file that starts using core code -> human
```

`~/.claude/kit/bin/review_tier.py` reads the policy **from the base branch**, so a pull request can't loosen its own rules.
A change is **human** when any of these hold, and each one is listed as a reason:

1. A changed path matches a `human` line, or matches no line at all.
2. A renamed file's **old** path is human: moving core code into an agent folder doesn't dodge review.
3. `.review-tiers` itself changes.
4. A test file is deleted, loses assertions, or gains `skip`/`xfail`/`.only`, or a runnable test is renamed to a
   name no runner collects. Runnable means a real runner pattern: `test_*.py`, `*_test.py`, `*_test.go`,
   `*.test.{js,jsx,ts,tsx}`, `*.spec.{js,jsx,ts,tsx}`, anything under `__tests__/`, and `tests/test_*.sh`
   (`latest.py` or `testing/guide.md` are not tests).
5. An agent-tier file adds a line matching an `escalate` pattern, for example a UI file importing auth code.
6. The change can't be fully read (a huge diff, a truncated file list, an API error). It fails closed.

The example policy also makes `conftest.py` (any depth), `.claude/**` and `CLAUDE.md` (any depth) human, even
inside an agent-tier folder: they change how tests run or how the agent behaves.

## Day to day

- **Lanes:** before reporting "ready", run `python3 ~/.claude/kit/bin/review_tier.py --local` and paste the tier into the
  PR. For `human`, start the title with `[HUMAN REVIEW]` and list the core files to read first.
- **Verifier:** reviews as usual and records the tier. Its `VERIFIED` never replaces the human review. If it sees
  backend logic sitting in an `agent` path, it raises a finding so the policy gets a new `human` line.
- **Merge queue:** agent-tier PRs merge on `VERIFIED`. Human-tier PRs print
  `NEEDS HUMAN REVIEW (core code): <files>` and wait. Repos without `.review-tiers` keep the plain verifier gate.
- **You:**
  - `~/.claude/kit/bin/human-queue.sh <owner/repo>` lists what waits on you, with the reasons, the files and the exact
    approve command. Add `--notify` for a desktop notice, or `--label` to tag those PRs `needs-human-review`.
  - Read the diff: `gh pr diff <n> -R <owner/repo>`.
  - Approve by typing it yourself, with a leading `!` in any Claude pane:
    `! ~/.claude/kit/bin/human-approve.sh <owner/repo> <n> <full sha>`. The approval covers that sha only; a new push
    needs a new look. Sessions are blocked from running this script or writing its record.
  - **On a team, use GitHub reviews instead.** Set `HUMAN_REVIEWERS=alice,bob` (GitHub logins) for the merge
    queue. Then a human-tier PR needs an `APPROVED` review from one of them **at the exact head commit**, and the
    local approval file stops counting (set `ALLOW_LOCAL_APPROVALS=1` to keep both). List only accounts whose
    credentials are not on the agent machine; the account your sessions use opens the PRs, and GitHub doesn't
    let an author approve their own PR. Optionally set `VERIFIER_LOGIN` so
    only that account's `VERIFIED` comment counts.
  - Weekly, spot-check agent-only merges: `~/.claude/kit/bin/human-sample.sh 5 7 <owner/repo>`.

## Let GitHub enforce it too

Where your plan allows it, add a server-side gate. It's stronger than any local script.

- **Plans:** branch protection, CODEOWNERS and rulesets on **private** repos need GitHub Pro, Team or Enterprise.
  On Free they work on public repos only. Check yours first: `gh api orgs/<org> --jq .plan.name`.
- **CODEOWNERS from the policy:** `python3 ~/.claude/kit/bin/review-codeowners.py @<human> > .github/CODEOWNERS`. It
  starts with "everything needs a human", leaves agent paths unowned, and repeats human paths last, because
  GitHub uses the last matching line.
- **Ruleset on `main`:**
  - require a pull request;
  - require review from Code Owners;
  - require the most recent push to be approved by someone else;
  - dismiss stale approvals;
  - an **empty bypass list**.
- **Use a separate human account:** a PR's author can't approve it, and agents open PRs as your account. Only a
  **second account's** approval proves a person looked, and its credentials must never sit on the agent machine.
- **Test before relying on it:** on a scratch repo, check that a core-path PR shows "blocked". The docs don't say
  whether code-owner review still blocks when "required approvals" is 0.

## Limits, plainly

- Every local session runs as the same OS user. The local gate stops mistakes and keeps approvals from being passed
  between sessions; it doesn't stop a deliberately hostile process. The server-side ruleset does more.
- Keep the merge scripts and the policy file in the `human` tier, so changing the gate needs a person.
- A label is for visibility only: any session can set one. The approval record, or a second account's review, is
  the proof.

Sources, all read 2026-10-09, are in `docs/research/RESEARCH-REVIEW-TIERS-2026-10-09.md`:
- GitHub plan gating, "authors cannot approve their own pull requests", rulesets and CODEOWNERS last-match;
- SLSA Source L4 two-party review;
- Anthropic's risk-tiered review with sampling (vendor blog);
- Claude Code Review never approves or blocks.
