# Risk-tiered review for agent-written code: research (2026-10-09)

Scope: a solo developer plus one part-time reviewer runs many parallel coding agents, an AI
verifier on every PR, and a merge script. Goal: agents own UI/UX, tests and benchmarks end to end;
"core backend" (authn/authz, data access and privacy filters, IAM/infra, schema/migrations,
money/cost paths, security-sensitive code) must get a HUMAN review before merge.
All sources read 2026-10-09. "Secondary" marks blogs and vendor pages. Where the docs are silent,
this says so; statements marked "(inference)" are reasoning from the docs, not quotes.

## Summary

| # | Finding | Recommendation for this setup | Source |
|---|---|---|---|
| 1 | Branch protection, CODEOWNERS and rulesets work on PRIVATE repos only on Pro, Team or Enterprise. Free (personal or org) gets them on public repos only. | Check each org's plan. Free org: GitHub can't enforce anything, so the merge script is the only gate. Team: use native rules. **ADOPT** a plan check first. | [P1] [P2] [P3] |
| 2 | "Pull request authors cannot approve their own pull requests." | The shared agent/owner account can never satisfy a required review on its own PRs. Any approval that counts has to come from a second account. **ADOPT** as the core proof. | [P4] |
| 3 | Admins bypass classic branch protection unless "apply to administrators" is set. Rulesets exempt nobody unless they are on the bypass list. | Use rulesets with an EMPTY bypass list. Take the Administration permission away from the agents' token (inference: an admin token can just edit the rule). **ADOPT.** | [P5] [P6] |
| 4 | The rulesets "required reviewer" rule (GA 2026-02-17) requires N approvals from named TEAMS on path patterns, with `!` negation, up to 15 teams. | Org repos on Team: one rule for the core-path globs, team = human reviewers only. Personal repos have no teams (inference), so use CODEOWNERS there. **ADOPT** (org, Team plan). | [P3] [P7] |
| 5 | CODEOWNERS: the last matching pattern wins, and a pattern with no owners leaves files unowned. | Default-deny: `* @human` first, then explicitly ownerless agent-only globs. Unlisted paths fall to a human. **ADOPT.** | [P8] |
| 6 | "Require approval of the most recent reviewable push" + "dismiss stale approvals". | Stops an agent pushing after the human approves. **ADOPT.** | [P5] |
| 7 | Copilot cloud agent: the user who asked for the PR can't approve it, branch protection still applies, and workflows wait for a write-access human. | Same model here: the requester/agent identity ≠ the approver identity. **ADOPT** the pattern. | [P9] |
| 8 | Claude Code Review findings "don't approve or block your PR"; its check run is always neutral. | The AI verifier is evidence, not a gate. The merge script gates on it for agent-only tiers. **ADOPT.** | [P10] |
| 9 | Anthropic tiers its codebase by risk: some codebases keep strict human approval, and a risk-weighted sample of AI-approved merges gets a human look. | Two tiers plus sampling of agent-only merges. **ADOPT.** | [P11] (secondary: vendor blog) |
| 10 | SLSA Source L4 two-party review: "two or more trusted persons". A "Trusted Robot" may get an explicit exception. | The core tier ≈ two-party (agent author + human). The agent-only tier is a declared robot exception. **ADOPT** the framing. | [P12] |
| 11 | Environment required reviewers on private repos: Enterprise only. | **SKIP**: not available on Pro or Team. | [P13] |
| 12 | Signed commits prove a key signed, not that a human reviewed (inference; docs silent). | **SKIP** as human proof; agents can sign with the same key. | — |
| 13 | OpenSSF: AI code is "not a shortcut around … code reviews, testing". OWASP Agentic Top 10: human approval for high-impact actions. | Supports the core tier. Neither says which paths. **ADOPT** as policy citation only. | [P14] [S1] |

## 1. Plan and account availability (private repos)

- Protected branches: "available in public repositories with free user and free team plans for
  organizations … in public and private repositories with Pro, Team, GitHub Enterprise Cloud, and
  GitHub Enterprise Server". [P1]
- CODEOWNERS: the same gating. Public only on Free (personal or org); private on Pro, Team and
  Enterprise. [P2]
- Rulesets: "public repositories with free user and free team plans for organizations, and in
  public and private repositories with pro, team, and GitHub Enterprise Cloud". Push rulesets
  (e.g. "Restrict file paths") are Team or above, on private/internal repos. [P3]
- Path-based required reviewers: the "required reviewer" rule went GA 2026-02-17. It requires
  approvals from specific teams when matching files change, with `!` negation, and up to 15 teams
  each with its own approval count. [P3] [P7] The changelog doesn't name plans. Because it needs
  teams and teams exist only in orgs, it is an org-only feature (inference). Docs silent on Pro.
- Personal account: with Pro, a personal private repo gets branch protection with required
  approvals and CODEOWNERS (owners must be collaborators with write access). [P1] [P2] If the
  personal account is on Free, nothing can be enforced on a private repo. The claim that "a
  personal account can't require reviewers" is true only on Free; re-check the plan.
- Action: run `gh api orgs/<org> --jq .plan.name` as an org owner to learn Free vs Team.
  - **ADOPT**: cheap, and every later choice depends on the answer.
  - **LATER**: moving a Free org to Team, if the human gate must be server-enforced (see the
    pricing page; not checked here).

## 2. Proving a human approved

- GitHub won't let an author approve their own PR. [P4] Because every agent opens PRs as the
  owner account, that account's approval never counts. A satisfied "required approvals" rule
  therefore implies a second account approved. Make sure that account's credentials (token,
  passkey) are never on the agent machine. This is the proof.
  - **ADOPT**: the part-time reviewer's account is the approver for the core tier.
  - **ADOPT**: the developer's own separate "human" account (2FA, no PAT, never logged into `gh`
    on the agent host) as a second approver, so the core tier isn't blocked on one person.
- Admin bypass is the hole. Classic protection exempts admins unless told not to. [P5] Rulesets
  exempt only the bypass list. [P6] The agents run as the owner, so they could edit or disable
  the rule itself (inference).
  - **ADOPT**: rulesets with an empty bypass list.
  - **ADOPT**: give agents a fine-grained token, or a GitHub App, WITHOUT the "Administration"
    permission. Keep the owner's admin credential out of agent sessions.
- GitHub App identity for agents: PRs are authored by `app[bot]`. Commits and the audit log then
  separate agent work from human work, and a ruleset can name the App in the bypass list or keep
  it off. Copilot's agent uses the same separation. [P9]
  - **LATER**: worth it once agents scale. It's not needed for the proof in the first bullet,
    which already works with the shared account.
- "Allow GitHub Actions to create and approve pull requests" is off by default for new personal
  repos. [P15]
  - **ADOPT**: keep it off, so an Actions workflow can't become an approver.
- Environment required reviewers with "prevent self-review" would be a nice second gate, but on
  Free/Pro/Team they work on public repos only. [P13]
  - **SKIP.**
- Signed commits: they attest to a key. Agents on the same host use the same key (inference).
  - **SKIP** for human proof. Keep them if already used for integrity.

## 3. Industry guidance on AI-code review by risk

- Anthropic: "We tier our codebase by risk, and make deliberate decisions on what parts to
  automate. Entire codebases have strict human approval processes." It also says "Every approval
  is logged with the signals and reasoning behind it, and a risk-weighted sample is reviewed by
  humans." [P11] (vendor blog, 2026-07-21)
  - **ADOPT** both: the tier split, and sampling of agent-only merges.
- Claude Code Review: findings "don't approve or block your PR"; the check run "always completes
  with a neutral conclusion". To gate, parse the severity JSON in your own CI. `REVIEW.md` can
  hold tier-specific rules ("Always check: queries scoped to the caller"). [P10]
  - **ADOPT**: the merge script reads the verifier result; `REVIEW.md` lists the core-path rules.
- Claude Code security docs: "You're responsible for reviewing proposed code … Verify proposed
  changes to critical files." [P16] They are silent on path tiers.
- GitHub Copilot cloud agent: "Prevents the user who asked Copilot cloud agent to create a pull
  request from approving it". It is "subject to any branch protections and required checks", can
  only push to its `copilot/` branch, and workflows wait for "Approve and run workflows". [P9]
  - **ADOPT** the separation of identities. The docs don't define risk tiers.
- SLSA v1.2 Source L4: "Changes in protected branches MUST be agreed to by two or more trusted
  persons prior to submission". The review covers the final revision, and an org "MAY choose to
  grant a Trusted Robot a perpetual exception". [P12]
  - **ADOPT** as the vocabulary: the core tier is two-party, and the agent-only tier is a written
    robot exception.
- OpenSSF: "AI-generated code isn't a shortcut around engineering processes such as code reviews,
  testing…". It also says to generate negative tests for security-critical functions. [P14]
  General; no tiers.
- OWASP Top 10 for Agentic Applications 2026: human-in-the-loop for high-impact and
  privilege-escalation actions. [S1] (secondary summaries; primary not read)
- Google/Microsoft: no primary guidance on path-tiered human review of AI code was found in this
  pass. Docs silent / not found; don't cite them.

## 4. Practical patterns

**Two tiers, default-deny.** Human review for everything unless the path is explicitly
agent-only. A CODEOWNERS sketch for org repos (last match wins; an empty owner list means
unowned [P8]):

```
*                         @org/human-reviewers      # default: human
/web/src/components/**                              # agent-only (no owner)
/web/src/styles/**
/bench/**
/tests/ui/**
# core re-asserted AFTER agent globs so it can't be shadowed
/infra/**                 @org/human-reviewers
**/migrations/**          @org/human-reviewers
**/auth*/**               @org/human-reviewers
/.github/**               @org/human-reviewers      # CODEOWNERS, workflows, rulesets-as-code
/scripts/merge*           @org/human-reviewers      # the merge script itself
/REVIEW.md /CLAUDE.md     @org/human-reviewers
```

- **ADOPT.** Then add the ruleset "require PR" with "require review from Code Owners", "most
  recent push approved by someone else", "dismiss stale approvals", and an empty bypass list.
  [P3] [P5] On Team orgs, the required reviewer rule with the same globs is an equivalent or
  extra layer.
- Free org (no server enforcement): the merge script does the check itself. It asks the reviews
  API whether every PR touching a non-agent glob has an APPROVED review, at the head sha, from an
  allow-listed human login. If not, it refuses.
  - **ADOPT** now. It is weaker, because agents can edit the script, so the script and its glob
    file sit in the human tier and a CI check fails if they change without that approval.
- **Label `needs-human-review`.** The merge script or CI applies it automatically from the globs.
  Agents may add it but never remove it. A label isn't proof, because the shared account can set
  it; the approval from another account is the proof.
  - **ADOPT** for visibility only.
- **Tests and benchmarks agent-only, but guarded.** Tests under core paths stay in the human tier
  (they're covered by the core globs). For agent-only tests, a CI diff check escalates to human
  review on: a deleted test file, fewer `assert`/`expect` lines, a new `skip`/`xfail`/`.only`,
  loosened tolerances in bench thresholds, or a changed snapshot plus a source change in one PR.
  - **ADOPT.** Cheap, and it targets the known way agents fail ("make the check pass").
- **Stopping escape into agent-only paths.** A rename or delete of an owned file touches an owned
  path, so the code-owner rule fires (inference from path matching). New logic copied into a UI
  path is the real gap. Mitigations:
  - **ADOPT**: an import/content guard in CI. A file under an agent-only glob may not import the
    DB client, cloud IAM/SDK clients, auth/session modules or secrets loaders, or contain raw SQL.
    If it does, the PR escalates.
  - **ADOPT**: the AI verifier's `REVIEW.md` rule: "flag server-side, data-access or auth logic
    added outside core paths as Important".
  - **ADOPT**: weekly risk-weighted sampling of agent-only merges by the human. [P11]
  - **LATER**: Claude Code `PreToolUse` hooks that deny agent edits to core globs without a ticket
    flag. That is prevention, not proof.
- Push rule "Restrict file paths" (Team, private): it blocks pushes touching a path outright, for
  everyone, with path exceptions since 2026-08. [P3]
  - **SKIP**: too blunt, since humans need to push core changes too.

## Sources (all read 2026-10-09)

- P1 https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/protected-branches.md
- P2 https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/code-owners.md
- P3 https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets and https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/repo-rules.md
- P4 https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews
- P5 https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches
- P6 https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
- P7 https://github.blog/changelog/2026-02-17-required-reviewer-rule-is-now-generally-available/ (and 2025-11-03 preview changelog)
- P8 https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
- P9 https://docs.github.com/en/copilot/concepts/agents/cloud-agent/risks-and-mitigations and https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent
- P10 https://code.claude.com/docs/en/code-review
- P11 https://claude.com/blog/how-anthropic-secures-its-ai-native-software-development-lifecycle (secondary: vendor blog, 2026-07-21)
- P12 https://slsa.dev/spec/v1.2/source-requirements
- P13 https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- P14 https://best.openssf.org/Security-Focused-Guide-for-AI-Code-Assistant-Instructions.html
- P15 https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository
- P16 https://code.claude.com/docs/en/security
- S1 (secondary) https://goteleport.com/blog/owasp-top-10-agentic-applications/ ; https://neuraltrust.ai/blog/owasp-top-10-for-agentic-applications-2026

Caveats:

- The page fetches went through a summarizing fetcher, so the quotes are as returned, not diffed
  against raw HTML.
- CODEOWNERS docs confirm the empty-owner behaviour verbatim: "Without an owner, changes … can be
  made with the approval of any user who has write access" [P8]. So agent-only PRs only merge
  without a human if the general "required approvals" count is 0, with code-owner review doing the
  gating. The docs don't say whether code-owner review still enforces at 0 required approvals.
  Prove it on a scratch repo before relying on it: a core-path PR must show "blocked".
- The plan for the required reviewer rule isn't stated anywhere I read.
