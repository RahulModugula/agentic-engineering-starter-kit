// OpenCode plugin: run the kit's guards before every tool call, and log shell commands after.
// Installed as ~/.config/opencode/plugins/agentic-kit.js (a link to this file). It hands each call to
// ~/.claude/hooks/agent-adapter.sh (KIT_ADAPTER overrides), the same guards Claude Code runs, and throws to block.
// It FAILS CLOSED: if the guard can't run, times out or answers something unreadable, the call is blocked.
// OpenCode has no end-of-turn hook that can keep the agent working, so "checks must pass before done" is advice here.
import { spawnSync } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

const adapter = () => process.env.KIT_ADAPTER || join(homedir(), ".claude", "hooks", "agent-adapter.sh")

function guard(event, payload) {
  return spawnSync("/bin/bash", [adapter(), "opencode", event], {
    input: JSON.stringify(payload), encoding: "utf8", timeout: 30000,
  })
}

function decide(r) {  // the adapter's answer -> null (run it) or the reason it's blocked
  if (r.error || r.status !== 0) return `agentic-kit: the guard couldn't run, so the call is blocked (${r.error?.message || r.stderr || `exit ${r.status}`}).`
  let d
  try { d = JSON.parse(r.stdout) } catch { return "agentic-kit: the guard's answer couldn't be read, so the call is blocked." }
  if (d.decision === "allow") return null
  return d.reason || "agentic-kit: blocked."
}

export const AgenticKit = async ({ directory }) => {
  const argsByCall = new Map()
  return {
    "tool.execute.before": async (input, output) => {
      const args = output?.args ?? {}
      const why = decide(guard("pre", { tool: input.tool, args, cwd: directory, session: input.sessionID ?? "" }))
      if (why) throw new Error(why)
      if (input.callID) argsByCall.set(input.callID, args)
    },
    "tool.execute.after": async (input) => {
      const args = argsByCall.get(input.callID) ?? input.args ?? {}
      argsByCall.delete(input.callID)
      guard("post", { tool: input.tool, args, cwd: directory, session: input.sessionID ?? "" })
    },
  }
}
