# Security policy

## Supported versions
Only the latest release gets security fixes while the project is at 0.y.z.

## Reporting a vulnerability
Please do **not** open a public issue. Use GitHub's private reporting: the **Security** tab, then **Report a
vulnerability**. Include the version, OS, steps to reproduce, and the impact. Examples: a way past a guard hook,
a secret the scanner missed, a human-review gate that let core code through, or the installer writing outside
`~/.claude`.

You'll get an acknowledgement within 3 days and a status update within 7 days. Once a fix ships, we publish a
GitHub Security Advisory and credit you, unless you'd rather not be named.

## Scope
In scope: the installer, hooks, the merge queue and its gates (verifier, review tiers, human approvals), the secret
scanner, and the ops helpers.
Out of scope: Claude Code itself (report that to its vendor), and attacks that need an already-compromised machine.
The threat model in `docs/ARCHITECTURE.md` says what the local guards do and don't stop.
