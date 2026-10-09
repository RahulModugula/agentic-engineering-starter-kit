# Launch research: agentic-starter-kit

Research date 2026-10-09. Every source below was read on 2026-10-09 unless marked otherwise.
**Primary** = the spec, platform docs or rules page itself. **Secondary** = blogs and commentary.
Where no primary source exists (for example, HN timing), the section says so instead of guessing.

## 1. Checklist

| Item | Why | Source |
|---|---|---|
| README in root: one-line "what it is", demo, 60-second quickstart, why different, safety model, FAQ, help, maintainer | GitHub says a README should cover what the project does, why it's useful, how to start, where to get help, and who maintains it. Content past 500 KiB is truncated. Use relative links. | [GitHub: About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes) (primary, read 2026-10-09) |
| LICENSE | You must include a license at launch. It also feeds the community profile and the Scorecard `License` check. | [opensource.guide: Starting a project](https://opensource.guide/starting-a-project/) (primary, read 2026-10-09) |
| CONTRIBUTING.md | Tells people how to report bugs, set up, and which contributions you want. | same; [GitHub: default community health files](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file) (primary, read 2026-10-09) |
| CODE_OF_CONDUCT.md (Contributor Covenant) | Gives you a linkable standard plus an enforcement route. v3.0 is listed as latest; v2.1 needs `[INSERT CONTACT METHOD]` filled in. | [contributor-covenant.org](https://www.contributor-covenant.org/) (primary, read 2026-10-09) |
| SECURITY.md + private vulnerability reporting | A community-profile item and the Scorecard `Security-Policy` check, which looks for contact info and disclosure wording. | [GitHub: private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository) (primary, read 2026-10-09) |
| SUPPORT.md | Tells people where to get help, which keeps questions out of Issues. | GitHub default community health files (above) |
| Issue forms in `.github/ISSUE_TEMPLATE/`, PR template | Issue templates are a community-profile item and only count in that folder. PR template locations: root, `docs/`, or `.github/pull_request_template.md`. | [GitHub: community profiles](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories); [GitHub: PR templates](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository) (primary, read 2026-10-09) |
| CITATION.cff (optional) | Only worth adding if researchers will cite the kit. Low priority for a dev tool. | GitHub: About citation files, docs.github.com (primary; not re-read today) |
| Topics (up to 20; lowercase, digits, hyphens; at most 50 chars each) | Make the repo discoverable, e.g. `claude-code`, `ai-agents`, `developer-tools`, `git-hooks`. | [GitHub: topics](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics) (primary, read 2026-10-09) |
| Social preview image, 1280x640 (min 640x320), PNG/JPG/GIF, under 1 MB | This is the card people see when the link is shared on HN, Reddit or chat. | [GitHub: social preview](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview) (primary, read 2026-10-09) |
| CHANGELOG.md (Keep a Changelog 1.1.0) | For humans, newest first, with an `Unreleased` section, ISO dates, and sections Added/Changed/Deprecated/Removed/Fixed/Security. | [keepachangelog.com 1.1.0](https://keepachangelog.com/en/1.1.0/) (primary, read 2026-10-09) |
| SemVer tags, starting at 0.y.z | "0.y.z is for initial development. Anything MAY change." 1.0.0 defines the public API. The tag `v1.2.3` is a convention; the version itself is `1.2.3`. | [semver.org](https://semver.org/) (primary, read 2026-10-09) |
| Releases: immutable, with a zip and a SHA-256 sum | An immutable release locks the tag and its assets and auto-generates a release attestation. Create it as a draft, attach the assets, then publish. | [GitHub: immutable releases](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases) (primary, read 2026-10-09) |
| Signed tags (`git tag -s`, `git tag -v`) | Proves that you cut the release. | [GitHub: signing tags](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-tags) (primary, read 2026-10-09) |
| Badges: CI status and license | The CI badge format is `https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg`. Add `?branch=main` to scope it to main. | [GitHub: status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge) (primary, read 2026-10-09) |
| GitHub Discussions | For conversations that don't need tracking, which keeps Issues for bugs. Enable it under Settings > Features. | [GitHub: Discussions quickstart](https://docs.github.com/en/discussions/quickstart) (primary, read 2026-10-09) |
| OpenSSF Scorecard checks | Third-party users judge supply-chain hygiene from this score (see section 5). | [ossf/scorecard checks.md](https://github.com/ossf/scorecard/blob/main/docs/checks.md) (primary, read 2026-10-09) |
| Actions pinned to a full 40-char commit SHA; `permissions: contents: read` | A full SHA is "currently the only way to use an action as an immutable release". The token should default to read-only. | [GitHub: Actions security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions) (primary, read 2026-10-09) |
| No secrets or private material in git history | This is on opensource.guide's pre-launch checklist. Run your own secret scanner over the full history before the first push. | opensource.guide: Starting a project (above) |
| Demo GIF made with vhs or asciinema | Shows in about 10 seconds what a reader would otherwise have to install to see. | Section 6 |

## 2. What an excellent repo has

**GitHub's community profile** (Insights > Community Standards) checks for: README, CODE_OF_CONDUCT,
LICENSE, CONTRIBUTING, security policy and issue templates
([about community profiles](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories),
primary, read 2026-10-09). GitHub also supports SUPPORT.md, FUNDING.yml, ACCESSIBILITY.md,
discussion category forms and VULNERABILITY_REPORT.yml (default community health files page, above).
Ship the profile items at 100% on day one.

**Suggested README order.** GitHub specifies what a README should contain, not the order. The order
below is a judgment call built on that list:
1. Name, plus one line saying what it does and who it is for. Example: "A tested Claude Code setup for
   running parallel AI coding sessions safely: guard hooks, a verified merge queue, and a secret
   scanner."
2. Badges: CI status, license, latest release. Keep it to three or four.
3. The demo GIF: about 20 seconds, showing a guard hook blocking something.
4. A 60-second quickstart: `git clone`, then `make install-dry-run`, then `make install`, then a
   first check. Show the commands and their expected output.
5. **Why it's different**: three bullets with evidence, such as the test count, what the kit blocks,
   and how rollback works.
6. **Safety model**: what the kit writes into `~/.claude`, what it never touches, how dry run and
   rollback work, and the human-review tiers for core code. For a tool that edits a user's agent
   config, this section earns trust.
7. Docs links (relative): the from-scratch guide and the architecture doc.
8. FAQ: uninstall, Claude Code version support, OS support, "does it send data anywhere?"
9. Contributing, security, license, and maintainer.

## 3. License: MIT or Apache-2.0

| | MIT | Apache-2.0 |
|---|---|---|
| choosealicense.com summary | "short and simple permissive license with conditions only requiring preservation of copyright and license notices" | "permissive... Contributors provide an express grant of patent rights" |
| Patent grant | Not explicit | Explicit grant (§3). It terminates for anyone who sues claiming the work infringes their patents. |
| Extra conditions | Keep the notice | Keep the notice, mark changed files, and pass on any NOTICE file (§4(d)) |

Sources: [choosealicense.com/licenses](https://choosealicense.com/licenses/) and
[apache.org LICENSE-2.0](https://www.apache.org/licenses/LICENSE-2.0) (both primary, read 2026-10-09).

**Recommendation: MIT.** The kit is shell scripts, hooks and docs that people will copy into their
own dotfiles and repos. MIT's single condition makes that copying frictionless. The patent
retaliation clause, which is the main thing Apache-2.0 adds, protects little in a config-and-scripts
kit. Choose **Apache-2.0** instead if you expect corporate contributors or want the explicit
contributor patent grant. In that case, add a NOTICE file only if you have attributions to carry;
Apache does not require one.

**Before publishing, the owner must confirm they own the rights to every file.** Code written for an
employer, or on employer time or equipment, may belong to the employer under the employment
agreement. Write the kit fresh, check the agreement, and copy nothing from work repos. Neither
license fixes a rights problem.

## 4. Launch

**Show HN rules** ([showhn.html](https://news.ycombinator.com/showhn.html), primary, read 2026-10-09):
- It must be "something you've made that other people can play with." A repo people can clone and
  run qualifies. Blog posts and landing pages don't.
- It must be non-trivial ("Don't post quickly-generated one-offs"). You must have worked on it
  personally and be "around to discuss" it.
- It must be ready for users and easy to try, with no sign-up or email gate.
- Begin the title with `Show HN:`. Later feature updates usually don't qualify for another Show HN;
  a major overhaul probably does.
- Never ask friends to upvote.

**HN guidelines** ([newsguidelines.html](https://news.ycombinator.com/newsguidelines.html), primary,
read 2026-10-09): "Don't solicit upvotes, comments, or submissions." No uppercase titles, exclamation
points or self-praise. Posting your own work is fine "part of the time".
Example title: `Show HN: Agentic-starter-kit – guard hooks and a merge queue for parallel Claude Code`.

**Timing.** HN publishes no guidance on posting time, and I found no primary source on it. Any
"best hour" advice is secondary and anecdotal. What you control: post when you can stay in the
thread for the next 4–6 hours.

**Reddit.** I could not fetch Reddit's help pages from here (HTTP 403, and the tool can't reach
reddit.com), so I have no primary citation. Every subreddit sets its own self-promotion rules in its
sidebar and wiki. Read them before posting, and only post where tools like this are explicitly
on-topic.

**Promotion in general** ([opensource.guide: Finding users](https://opensource.guide/finding-users/),
primary, read 2026-10-09): target "communities that will benefit," keep one focal URL, and help
others first. It may take a long time before people notice your project.

**First post template** (HN text field, or a Reddit body):
> I run several Claude Code sessions in parallel and kept hitting the same failures: two sessions
> editing one checkout, a secret pasted into a commit, a merge nobody verified. This kit is the setup
> I ended up with: guard hooks, a merge queue that only merges a verified commit, review tiers for
> core paths, and a secret scanner. The installer has a dry run and a rollback, so you can see every
> file it would write to ~/.claude first. What it doesn't do: [limits]. I'd value feedback on the
> safety model in particular.

That's a problem you hit yourself, what you built, its honest limits, and a specific question.
Avoid superlatives.

**The first week:**
- Reply to every issue within a day, even if only to say "reproduced, looking."
- Label issues (`bug`, `question`, `good first issue`) and move questions to Discussions.
- Ship a 0.1.1 with the fixes, and credit reporters in the CHANGELOG.
- Fix README gaps people ask about; repeated questions mean the README is missing something.

**On stars:** star counts can't be engineered within HN's rules, and trying breaks them. What you
control are the quality signals: a 100% community profile, green CI on two OSes, a good Scorecard
score, signed and immutable releases, a working dry run, and fast, polite replies.

## 5. Supply chain and safety, for a kit that writes to ~/.claude

**Scorecard checks worth passing**
([checks.md](https://github.com/ossf/scorecard/blob/main/docs/checks.md), primary, read 2026-10-09):

| Check | Risk | What to do |
|---|---|---|
| Dangerous-Workflow | Critical | Avoid `pull_request_target` and `workflow_run` with untrusted checkouts. Never interpolate `${{ github.event.* }}` into `run:`. |
| Token-Permissions | High | Set `permissions: contents: read` at the top level, and grant writes per job only. |
| Branch-Protection | High | Protect `main`: no force-push, require the CI status check, require a PR. |
| Code-Review | High | Merge through PRs. As a solo maintainer, use the kit's own verifier gate. |
| Signed-Releases | High | Attach `.sig`/`.asc`/`.minisig` (8 points) or SLSA `.intoto.jsonl` provenance (10 points). |
| Pinned-Dependencies | Medium | Pin actions to SHAs, and pin any download in the scripts. |
| Security-Policy, License, CI-Tests | Med/Low | Covered by the templates below. |
| Dependency-Update-Tool, Maintained, SAST | High/High/Med | Dependabot for actions; keep committing; optionally add CodeQL or shellcheck. |

**Releases.** Build the zip in CI from the tag, publish `SHA256SUMS`, and use an immutable release so
its auto-generated attestation covers the assets (immutable releases doc, above). Sign the tag with
`git tag -s v0.1.0` and verify it with `git tag -v v0.1.0` (signing tags doc, above). For
reproducibility, build the archive from the tag with `git archive --format=zip`, which takes its
content and metadata from the tagged commit, not the working tree. Confirm two builds give the same
SHA-256 before claiming it's reproducible.

**Don't use "curl | bash".** The secondary sources agree on the risks: there's no integrity check;
the server can detect a pipe to bash and serve different content (a time-of-check to time-of-use
gap); and the script runs before the download finishes
([Sysdig: Friends don't let friends curl|bash](https://www.sysdig.com/blog/friends-dont-let-friends-curl-bash),
secondary, read 2026-10-09; [lobste.rs thread](https://lobste.rs/s/ymcbwl/what_s_problem_with_pipe_curl_into_sh),
secondary, read 2026-10-09). The kit's documented path should be: clone, or download the release and
`shasum -a 256 -c SHA256SUMS`; read the code; then dry run; then install, with rollback on hand.

## 6. Recording a terminal demo

**vhs** ([charmbracelet/vhs](https://github.com/charmbracelet/vhs), primary, read 2026-10-09).
Scripted runs are reproducible, so you can re-record the GIF on every release. It needs `ttyd` and
`ffmpeg` on PATH.
```sh
brew install vhs
vhs new demo.tape     # scaffold a tape
vhs demo.tape         # render it
```
```
Output demo.gif
Require make
Set FontSize 22
Set Width 1200
Set Height 600
Type "make install-dry-run"
Enter
Sleep 3s
```
Settings must come at the top of the tape (TypingSpeed is the exception).

**asciinema** ([docs.asciinema.org/getting-started](https://docs.asciinema.org/getting-started/),
primary, read 2026-10-09). This records a live session, and the text stays selectable in the player.
```sh
brew install asciinema
asciinema rec demo.cast      # Ctrl+D or `exit` to stop
asciinema play demo.cast
agg demo.cast demo.gif       # GIF for the README
```
Use vhs for the README GIF, and asciinema if you want a copyable recording to link.

## 7. Templates

### SECURITY.md
```markdown
# Security policy

## Supported versions
Only the latest release receives security fixes while the project is at 0.y.z.

## Reporting a vulnerability
Please do **not** open a public issue. Use GitHub's private reporting: the
**Security** tab, then **Report a vulnerability**. Include the version, OS, steps to reproduce, and
the impact (for example, a guard hook bypass, a secret the scanner missed, or the installer writing
outside `~/.claude`).

You'll get an acknowledgement within 3 days and a status update within 7 days. Once a fix is
released, we publish a GitHub Security Advisory and credit you unless you prefer not to be named.

## Scope
In scope: the installer, hooks, merge queue, verifier gate and secret scanner.
Out of scope: Claude Code itself (report that to its vendor) and issues needing a compromised machine.
```
(This requires private vulnerability reporting to be enabled under Settings > Advanced Security.)

### CONTRIBUTING.md
```markdown
# Contributing

Thanks for helping. Bug reports, docs fixes and new guard hooks are all welcome.

1. Open an issue first for anything bigger than a typo, so we can agree on the approach.
2. Fork, then branch from `main`.
3. Run `make check` before pushing. CI runs the same target on Ubuntu and macOS.
4. Changes to core paths (installer, hooks, merge queue) need a test that fails without your change.
5. Add a line under `## [Unreleased]` in CHANGELOG.md.
6. Open a PR and fill in the template.

Questions go to Discussions, not Issues. Be kind: see CODE_OF_CONDUCT.md.
By contributing, you agree your work is licensed under this project's LICENSE.
```

### .github/pull_request_template.md
```markdown
## What and why
<!-- One or two sentences. Link the issue: Fixes #123 -->

## How it was verified
<!-- The commands you ran and what they printed. -->
- [ ] `make check` passes locally
- [ ] Ran the installer's dry run and rollback, if the installer changed

## Risk
- [ ] Touches a core path (installer, hooks, merge queue, secret scanner): needs maintainer review
- [ ] CHANGELOG.md updated under Unreleased
- [ ] Docs updated, if behaviour changed
```

### .github/ISSUE_TEMPLATE/bug_report.yml
Uses the issue-forms syntax
([GitHub: syntax for issue forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms),
primary, read 2026-10-09). The required keys are `name`, `description` and `body`. The body element
types are markdown, input, textarea, dropdown, checkboxes and upload.
```yaml
name: Bug report
description: Something in the kit did not work as documented.
title: "[Bug]: "
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: "Thanks for reporting. Please remove any secrets or tokens from logs before pasting."
  - type: input
    id: version
    attributes:
      label: Kit version
      placeholder: "0.1.0"
    validations:
      required: true
  - type: dropdown
    id: os
    attributes:
      label: Operating system
      options: ["macOS", "Linux", "Other"]
    validations:
      required: true
  - type: dropdown
    id: component
    attributes:
      label: Component
      options: ["Installer", "Guard hooks", "Merge queue / verifier", "Secret scanner", "Docs"]
    validations:
      required: true
  - type: textarea
    id: repro
    attributes:
      label: Steps to reproduce
      placeholder: "1. Run make install-dry-run\n2. ..."
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Expected vs actual
    validations:
      required: true
  - type: textarea
    id: logs
    attributes:
      label: Output
      render: shell
  - type: checkboxes
    id: checks
    attributes:
      label: Checks
      options:
        - label: I searched existing issues.
          required: true
        - label: This is not a security vulnerability (those go to SECURITY.md).
          required: true
```

### .github/workflows/ci.yml
Pinning format: the full 40-character commit SHA, with the tag in a trailing comment. GitHub's
hardening guide calls this "the only way to use an action as an immutable release". A short SHA or
a tag doesn't qualify. The SHA below is `actions/checkout` tag `v7.0.1`, which I read twice from the
GitHub API on 2026-10-09
([ref](https://api.github.com/repos/actions/checkout/git/ref/tags/v7.0.1)). Re-check it yourself
before the first commit (`gh api repos/actions/checkout/git/ref/tags/v7.0.1 --jq .object.sha`), and
let Dependabot bump it after that.
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  check:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Run checks
        run: make check
```
Notes:
- The matrix syntax follows [GitHub: running variations of jobs](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/running-variations-of-jobs-in-a-workflow)
  (primary, read 2026-10-09).
- `fail-fast: false` lets the macOS job still report when the Ubuntu job fails.
- `persist-credentials: false` keeps the token out of `.git/config`, so `make check` can't push with
  it.
- Add `.github/dependabot.yml` with `package-ecosystem: github-actions` to keep the pinned SHA
  current. That also covers the Scorecard Dependency-Update-Tool check.
