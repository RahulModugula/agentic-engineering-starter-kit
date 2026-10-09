# For engineering leaders

What this setup gives a team, what it costs, where people stay in control, and how to roll it out and measure it.
Read in five minutes; details are in `docs/ARCHITECTURE.md`.

## What it gives you

- **More output from the same people.** One engineer directs several AI sessions at once: a coordinator plans,
  lanes build in isolated copies of the repo, a verifier reviews every change. People spend their time on
  direction, review and the hard problems.
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

- **Licences:** each person needs a Claude plan that includes Claude Code (Pro or higher; check claude.com/pricing).
  Running several sessions at once uses more of a plan's allowance, so heavy users typically need a higher tier.
- **Setup:** about an hour per person with `START-FROM-SCRATCH.md`; installing is reversible with one command.
- **Ongoing:** reviewing the core-code queue. That time is the point: it keeps a person accountable for what
  matters.

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
