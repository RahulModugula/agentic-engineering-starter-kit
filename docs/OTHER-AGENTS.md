# Other agent CLIs, and coding with no AI subscription

Claude Code is the default and gets every guard. The same guards also run in **Codex CLI**, **OpenCode** and
**Antigravity CLI** (Google's replacement for Gemini CLI), and the kit's rules work in any tool that reads
`AGENTS.md` (Cursor, GitHub Copilot and others). The hooks themselves don't change: `claude/hooks/agent-adapter.sh`
turns each tool's hook input into the shape Claude Code uses, runs the same scripts, and answers in the tool's own format.

```
./install.sh --tool all              # dry run: what Codex, OpenCode and Antigravity would get
./install.sh --apply --tool all      # or --tool codex,opencode; default: each one found on PATH
./install.sh --rollback              # undoes it, every tool's files included
```

## What each tool gets

| | Claude Code | Codex CLI | OpenCode | Antigravity CLI | Cursor, Copilot, others |
|---|---|---|---|---|---|
| Kit rules (`AGENTS.md`) | `~/.claude/CLAUDE.md` import | `~/.codex/AGENTS.md` | `~/.config/opencode/AGENTS.md` | `~/.gemini/AGENTS.md` | copy into each repo (below) |
| Shell guard (no push to main, no lane merges, no pattern kills, controls owner-only) | yes | yes | yes | yes | no |
| Test lock on file edits (including every file in a patch) | yes | yes | yes | yes | no |
| Secrets unread, guard files unedited (the `Read(...)`/`Edit(...)` rules) | permission rules | file-guard on edits; reads go through the shell, as in Claude Code | file-guard | file-guard | no |
| "Done" means the checks pass (Stop hook) | yes | yes | **no**: OpenCode has no stop hook that can keep the agent working | yes (checks only) | no |
| Audit log of shell commands | yes | yes | yes | yes | no |
| Prod-AWS "ask" | asks | **denied**, run it yourself | **denied** | **denied** | no |
| `coord` / `lane` (`LANE_TOOL=codex lane 1`) | yes | yes | yes | yes, paste the first message | no |

"Ask" becomes "deny" because none of these tools can ask through a hook yet. The reason they show says so, and
you can still run the command yourself.

**Fails closed, within limits.** The adapter blocks the call when:
- `jq` is missing;
- it can't read the input;
- a guard crashes, or all the checks for one call take longer than 15 seconds (`KIT_GUARD_TIMEOUT`; a patch touching
  many files may need splitting);
- a file edit names no path it can find.

If the adapter itself can't start, the outcome is up to the tool: OpenCode's plugin blocks, while Codex's and
Antigravity's docs don't say. Antigravity's hook `timeout` is in seconds, per its docs.

**Searches can still read secrets.** A search or listing aimed at a protected path is checked, so `grep` in `.env`
or `~/.ssh` is blocked. A search over the whole project can still read `.env`, the same as in Claude Code.

**Before the guards run:**
- **Codex** runs new hooks only after you review them. Start `codex`, run `/hooks` once and trust the kit's.
- **Antigravity** reads `~/.gemini/config/hooks.json`. One third-party report (not confirmed) says some early versions
  loaded hooks without firing them. Check it once: in a scratch repo on `main`, ask it to run `git push origin main`.
  It must refuse with a `lane-guard` reason.
- **Cursor, Copilot and other `AGENTS.md` readers:** only the rules apply, as advice. Copy them into a repo with
  `cp ~/.claude/kit/claude/CLAUDE.md AGENTS.md`. Use a copy, not a link, so teammates get the file too.

**Limits, stated plainly:**
- The shell guard parses commands; it doesn't run them. It can't follow a variable (`D=~/.codex; rm -rf $D`) or a
  script that writes files itself. The same limit applies in Claude Code (see `docs/ARCHITECTURE.md`).
- The coordinator can't receive "ready at" messages from lanes in these tools; you pass them on.
- Tool names and hook formats come from each tool's docs as read on 2026-10-19 (sources below). The tests drive the
  adapter with those formats, but no test runs the real CLIs. If a tool renames a tool or a field, the guard may
  stop seeing that call. Re-run the check above after a major update.

## Coding with no AI subscription

For someone who wants to try this without paying for an AI plan, as of 2026-10-19:

| Option | What it costs | The catch |
|---|---|---|
| **OpenCode with a free model** | free (models marked "Free", most only for a limited time) | Check each model's data terms. See the warning below |
| **Antigravity CLI** (`agy`), Google account | free tier | The limits aren't published; community reports range from about 20 requests a day to a weekly cap |
| **Codex CLI**, ChatGPT Free account | reported as included in Free (OpenAI Help, as quoted by third-party guides; check your account) | Limits aren't published; sized for trying it, not daily work |
| **Local model** (Ollama with OpenCode) | free, private | Needs a strong laptop; local models are weaker |

Setup for the first option (after steps 1–2 of [`START-FROM-SCRATCH.md`](../START-FROM-SCRATCH.md), skipping the
Claude Code install):
```
curl -fsSL https://opencode.ai/install | bash          # OpenCode
git clone https://github.com/RahulModugula/agentic-engineering-starter-kit.git ~/agentic-starter-kit
cd ~/agentic-starter-kit && make check && ./install.sh --apply --tool opencode
```
Then run `opencode` in a project and choose a free model with `/models`.

> **Warning: free models and confidential data.** Some free models keep or train on what you send them. OpenCode's
> own docs (read 2026-10-19) list:
> - **No training, no retention:** GLM-5.3-Flash Free, DeepSeek V4.1 Flash Free, MiniMax M3.1 Flash Free and
>   LongCat 2.5 Preview Free.
> - **May train on your data, or retain it for 30 days:** Big Pickle, MiMo and Exo models, LL Alpha Free (both) and
>   Beam Free (retention).
> - **"Do not submit personal or confidential data":** the NVIDIA Nemotron models.
>
> Anything under a duty of confidentiality, such as client files, privileged material or personal data, should only
> go to a zero-retention model, a local model, or a paid plan whose terms you've read. That includes code that
> contains such material. The kit's file guard keeps `.env`, keys and credentials unread. It can't tell a client
> memo from a README.

## Sources (read 2026-10-19)

- Codex hooks: https://learn.chatgpt.com/docs/hooks (moved from developers.openai.com/codex/hooks)
- Codex AGENTS.md: https://developers.openai.com/codex/guides/agents-md
- OpenCode plugins and rules: https://opencode.ai/docs/plugins/, https://opencode.ai/docs/rules/
- OpenCode free models and their data terms: https://opencode.ai/docs/zen/
- Antigravity hooks and rules: https://antigravity.google/docs/hooks/, https://antigravity.google/docs/rules
- Gemini CLI replaced by Antigravity CLI on 2026-06-18: https://geminicli.com/docs/resources/quota-and-pricing/
