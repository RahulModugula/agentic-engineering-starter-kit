# For engineering leaders

What this setup gives a team, what it costs, where people stay in control, and how to roll it out and measure it.
Read in five minutes; details are in `docs/ARCHITECTURE.md`.

## What it gives you

- **More output from the same people, as the aim.** One engineer directs several AI sessions at once: a coordinator plans,
  lanes build in isolated copies of the repo, a verifier reviews every change. People spend their time on
  direction, review and the hard problems. Measure it in your own pilot (below) before counting on it.
- **Speed without losing control.** UI, tests, benchmarks and docs can ship on AI review alone. Core code (auth,
  data access and privacy, money, infrastructure, schemas, deploys) **waits for a person**, who sees exactly which
  files to read. You choose what counts as core, per repo, in one policy file.
- **Rules that actually hold.** The non-negotiables are enforced by code that runs before every action, not by
  instructions an AI may ignore: nothing pushed straight to main, nothing merged unverified, no secrets in shared
  repos, no unreviewed core code.
- **Proof, not promises.** Every rule has a test, and a mutation check shows each test fails when its rule is
  removed. `make verify` re-proves it in minutes, offline.

## The principle: as autonomous as the evidence allows

The aim is to let the AI do as much as it safely can, and to widen that as it earns trust. Agents already plan, build,
test, review and merge on their own; the guards are what make that safe to leave running. Autonomy grows in
measured steps:
- move a path from `human` to `agent` once sampled AI-only merges in it were sound;
- turn on green-main merging once main's CI has stayed green;
- let long jobs run unattended once their credentials, watchers and retries are in place.

Each step is a one-line policy change with a test behind it, so it's easy to make and easy to undo.

## Where people stay in charge

| Decision | Who | How it's enforced |
|---|---|---|
| What to build, and in what order | People | The coordinator plans; you approve |
| Risky actions: deploys, deletes, spending, production data | The person at the pane that asks | An approval typed in one session can't be passed on by another |
| Core code merging | A named person, at the exact commit | The merge queue waits; sessions can't record approvals; where your GitHub plan allows, server-side code-owner review |
| Everything else merging | The AI verifier plus green checks | The merge guard: exact commit, every check green |
| Spot-checks of AI-only merges | A person, weekly | `bin/human-sample.sh` picks them at random |

## What it costs

The kit itself is free and needs no new service. The cost is the Claude plan, setup time and review time.

| Plan (all include Claude Code) | Price per person per month | Fits |
|---|---|---|
| Pro | $20 monthly, or $17 billed yearly | Trying it; one or two sessions at a time |
| Max | from $100 | One person running several sessions most days |
| Team, Standard seat (2+ people) | $25 monthly, or $20 billed yearly | A team with light use |
| Team, Premium seat (2+ people) | $125 monthly, or $100 billed yearly | A team running parallel sessions daily |
| Enterprise | $20 per seat billed yearly, **plus usage** that scales with model and task | Large organisations needing central controls |

Prices from [claude.com/pricing](https://claude.com/pricing), read 2026-10-09; check before budgeting. Running
several sessions at once uses a plan's allowance faster, so people who work this way usually need Max or a
Premium seat.

- **Setup:** about an hour per person with `START-FROM-SCRATCH.md`; the install is undone with one command.
- **Ongoing:** reading the core-code review queue. That time is deliberate: a person stays accountable for what
  matters.
- **Payback, as a way to judge it:** a seat pays for itself if it saves its holder more hours a month than its
  price buys of their time. At a loaded cost of $100 an hour, a $125 seat needs about 1.25 saved hours a month.
  Measure the saving in your pilot (below) rather than assuming it.

### Keeping spend in check

- `/usage` in a session, and the status line, show how much of the plan is used.
- On usage-billed plans, set spend limits in the admin console.
- Unattended (scripted) runs can be capped per run: `claude -p --max-turns N --max-budget-usd X`. These flags
  apply in print mode only, and the dollar figure is Claude Code's estimate, not an invoice
  ([CLI reference](https://code.claude.com/docs/en/cli-reference), read 2026-10-09).
- The kit's rule that sessions stop after three failed check runs keeps a stuck session from burning allowance.

### A two-week pilot checklist

1. Pick one repo and one or two people. Record baseline numbers with `bin/measure.py`.
2. Install with `START-FROM-SCRATCH.md`; turn on review tiers with `default human`.
3. Run real tasks for two weeks. Each week, sample AI-only merges with `bin/human-sample.sh`.
4. Compare: merge wait, PRs verified first time, fixes needed after merge, hours saved (ask the people), plan usage.
5. Decide: stop, continue, or widen to the team, on those numbers.

## Risks, plainly

- **Local guards stop mistakes, not attackers.** Every session runs as the same user on the same machine. Use
  GitHub's server-side rules (rulesets and code-owner review from a separate human account) for the hard boundary;
  `docs/REVIEW-TIERS.md` shows how.
- **AI review is evidence, not accountability.** That's why core code needs a person and agent-only merges get
  sampled.
- **Tests can be gamed.** The setup locks tests during implementation, flags weakened tests, rewritten snapshots,
  new exclusions and flaky markers to a person, and uses mutation testing to show the tests have teeth.

## Rolling it out

1. **One person, one repo, one week.** Install and run real tasks. Turn on review tiers with a policy that is
   strict to start (`default human`).
2. **Measure:** run `bin/measure.py` before and after. It reports merge wait p50/p90, runs killed by expired
   credentials, and overnight stall minutes. Track how many PRs pass verification first time, and how many merged
   changes later needed a fix.
3. **Loosen deliberately.** Move paths to `agent` only when the evidence supports it: the sampled AI-only merges
   were sound.
4. **Then the team:** same install; one shared policy per repo, changed through review like any code.

## What to ask for in a review of this setup

- The test run (`make check`) and the mutation run (`make mutate`), on your machine.
- The review-tier policy for each repo, and who the human reviewers are.
- Whether GitHub's server-side rules are on for each repo.
- The before/after numbers from `bin/measure.py`.
