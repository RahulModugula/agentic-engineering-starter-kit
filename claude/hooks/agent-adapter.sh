#!/bin/bash
# agent-adapter.sh TOOL EVENT: run the kit's guards for an agent CLI other than Claude Code.
#   TOOL   codex | antigravity | opencode (opencode's plugin, tools/opencode/agentic-kit.js, calls this)
#   EVENT  pre (before a tool runs) | post (after; audit log) | stop (Antigravity's end of turn)
# It reads the tool's own hook JSON on stdin, turns each call into the Claude Code shape the hooks already take,
# runs the same hooks (lane-guard.sh for shell commands; tests-lock.sh and file-guard.sh for every file a call
# edits or reads, including each file named in an apply_patch patch), and answers in the tool's own format. The
# guards themselves don't change, so their tests cover every tool.
# Strictest answer wins. "ask" becomes "deny": none of these tools can ask through a hook yet, and the owner can
# still run the command themselves. It FAILS CLOSED before a tool runs: no jq, input it can't read, or a guard that
# crashes, or checks running past KIT_GUARD_TIMEOUT (15s in all, per call), block the call. post and stop never block on their own errors.
# If the adapter itself can't start, what happens is up to the tool (OpenCode's plugin blocks; see docs/OTHER-AGENTS.md).
TOOL=${1:-}; EV=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
case "$TOOL" in codex|antigravity|opencode) ;; *) echo "usage: agent-adapter.sh codex|antigravity|opencode pre|post|stop" >&2; exit 2;; esac
case "$EV" in pre|post|stop) ;; *) echo "usage: agent-adapter.sh $TOOL pre|post|stop" >&2; exit 2;; esac

deny() {  # deny REASON: answer "don't run it" in this tool's format, then stop
  local r="$1 [via agent-adapter for $TOOL]"
  case "$TOOL" in
    codex) jq -n --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null \
             || { echo "$r" >&2; exit 2; };;
    *) jq -n --arg r "$r" '{decision:"deny",reason:$r}' 2>/dev/null \
         || printf '{"decision":"deny","reason":"agent-adapter: blocked (jq is missing)"}\n';;
  esac
  exit 0
}
if ! command -v jq >/dev/null 2>&1; then
  [ "$EV" = pre ] && deny "jq is not installed, so the kit's guards can't read the call. Install jq."
  exit 0
fi
IN=$(cat)

# --- normalise: {kind: shell|edit|read|other, command, wd, edits: [paths], reads: [paths], nopath, cwd, sid} -------
# A patch's file names count as edits wherever the patch appears (Codex's apply_patch tool, or apply_patch run
# from the shell): "*** Add File: p", "*** Update File: p", "*** Delete File: p", "*** Move to: p". Patch parsers
# accept padding and CRLF line ends, so this does too (a stray \r once let a patch to a guard file through).
PATCHPATHS='[scan("(?m)^[ \\t]*\\*\\*\\* (?:Add|Update|Delete) File:[ \\t]*(.+?)[ \\t\\r]*$"), scan("(?m)^[ \\t]*\\*\\*\\* Move to:[ \\t]*(.+?)[ \\t\\r]*$")] | map(.[0])'
# wd: a shell tool's own working-directory argument; lane-guard decides which branch a bare push hits from it.
# nopath: a file edit with no path we can find is blocked, not waved through.
case "$TOOL" in
codex) N=$(printf '%s' "$IN" | jq -ec '
  (.tool_input // {}) as $i | (.tool_name // "") as $t
  | ($i.command // $i.cmd // "") as $c
  | (if ($c|type) == "array" then ($c|map(tostring)|join(" ")) else ($c|tostring) end) as $cmd
  | [$i | to_entries[] | select(.key | test("path|file"; "i")) | .value | strings] as $ps
  | {cwd: (.cwd // ""), sid: (.session_id // ""), command: $cmd, wd: ($i.workdir // ""),
     kind: (if $t == "apply_patch" or $t == "Edit" or $t == "Write" then "edit"
            elif $t == "Bash" or $t == "exec_command" or $t == "shell" or $t == "local_shell" then "shell" else "other" end),
     edits: (($cmd | '"$PATCHPATHS"') + $ps), reads: []}
  | if .kind == "edit" then .command = "" else . end
  | .nopath = (.kind == "edit" and (.edits | length) == 0)' 2>/dev/null);;
antigravity) N=$(printf '%s' "$IN" | jq -ec '
  (.toolCall.name // "") as $t | (.toolCall.args // {}) as $a
  | [$a | to_entries[] | select(.key | test("path|file|dir|dest"; "i")) | .value | strings] as $ps
  | {cwd: (.workspacePaths[0] // ""), sid: (.conversationId // ""), command: ($a.CommandLine // ""), wd: ($a.Cwd // ""),
     kind: (if $t == "run_command" then "shell"
            elif $t == "write_to_file" or $t == "replace_file_content" or $t == "multi_replace_file_content"
              or (($t | test("file"; "i")) and ($t | test("write|replace|edit|delete|remove|move|rename|create|patch"; "i"))) then "edit"
            elif ($ps | length) > 0 then "read" else "other" end)}
  | .edits = ((.command | '"$PATCHPATHS"') + (if .kind == "edit" then $ps else [] end))
  | .reads = (if .kind == "read" then $ps else [] end)
  | .nopath = (.kind == "edit" and (.edits | length) == 0)' 2>/dev/null);;
opencode) N=$(printf '%s' "$IN" | jq -ec '
  (.tool // "") as $t | (.args // {}) as $a
  | ([$a[] | strings | select(test("\\*\\*\\* Begin Patch"))] | join("\n")) as $patch
  | [$a | to_entries[] | select((.key | test("path|file|dir"; "i")) and .key != "workdir") | .value | strings] as $ps
  | {cwd: (.cwd // ""), sid: (.session // ""), command: (if $t == "bash" then ($a.command // "") else "" end), wd: ($a.workdir // ""),
     kind: (if $t == "bash" then "shell" elif $t == "edit" or $t == "write" or $t == "multiedit" or $t == "patch" or $t == "apply_patch" then "edit"
            elif $t == "read" or $t == "grep" or $t == "glob" or $t == "list" then "read" else "other" end)}
  | .edits = (((.command + "\n" + $patch) | '"$PATCHPATHS"') + (if .kind == "edit" then $ps else [] end))
  | .reads = (if .kind == "read" then $ps else [] end)
  | .nopath = (.kind == "edit" and (.edits | length) == 0)' 2>/dev/null);;
esac
if [ -z "$N" ]; then [ "$EV" = pre ] && deny "couldn't read the $TOOL hook input, so the call is blocked."; exit 0; fi
get() { printf '%s' "$N" | jq -r "$1"; }
CWD=$(get .cwd); SID=$(get .sid); KIND=$(get .kind); CMD=$(get .command); WD=$(get .wd)
SHELL_CWD=$CWD   # where a shell command really runs: its own working-directory argument, if it has one
case "$WD" in '') ;; /*) SHELL_CWD=$WD;; *) SHELL_CWD=$CWD/$WD;; esac
# When that differs from the session's folder, lane-guard is shown `cd <dir> && <command>`: its push checks then
# treat a bare push as unknown, and its controls check sees `rm hooks.json` run inside ~/.codex.
real() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }
GUARD_CMD=$CMD
[ "$(real "$SHELL_CWD")" = "$(real "$CWD")" ] || GUARD_CMD="cd '$SHELL_CWD' && $CMD"
# One time budget for every guard a call needs (a big patch runs two per file), under the tools' own hook timeouts.
BUDGET=${KIT_GUARD_TIMEOUT:-15}; case "$BUDGET" in ''|*[!0-9]*|0) BUDGET=15;; esac

with_timeout() {  # with_timeout SECONDS CMD...: kill CMD and everything it started after SECONDS (exit 124)
  perl -e '$t = shift; $p = fork; die unless defined $p;
    if (!$p) { setpgrp(0, 0); exec @ARGV; exit 126 }
    $SIG{ALRM} = sub { kill "KILL", -$p; exit 124 }; alarm $t; waitpid $p, 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$@"
}
run() {  # run HOOK JSON -> prints "deny<TAB>reason" when the hook blocks (exit 2, deny or ask); fails closed
  local o e rc; e=$(mktemp "${TMPDIR:-/tmp}/kitadapt.XXXXXX")
  local left=$((BUDGET - SECONDS))
  [ "$left" -gt 0 ] || { rm -f "$e"; printf 'deny\tChecking this call took longer than %ss, so it is blocked. Split it into smaller ones.\n' "$BUDGET"; return; }
  o=$(printf '%s' "$2" | HOOK_AGENT=$TOOL with_timeout "$left" "$HERE/$1" 2>"$e"); rc=$?
  local err; err=$(tail -c 2000 "$e"); rm -f "$e"
  if [ "$rc" = 2 ]; then printf 'deny\t%s\n' "${err:-$1 blocked this.}"; return; fi
  [ "$rc" = 124 ] && { printf 'deny\t%s took longer than %ss, so the call is blocked.\n' "$1" "$BUDGET"; return; }
  [ "$rc" = 0 ] || { printf 'deny\t%s failed (exit %s), so the call is blocked: %s\n' "$1" "$rc" "$err"; return; }
  [ -n "$o" ] || return 0
  local d r; d=$(printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecision // .decision // ""' 2>/dev/null) \
    || { printf 'deny\t%s gave output it could not read, so the call is blocked.\n' "$1"; return; }
  r=$(printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // ""' 2>/dev/null)
  case "$d" in
    deny|block) printf 'deny\t%s\n' "$r";;
    ask) printf 'deny\tThis needs your approval, and %s cannot ask through a hook, so it is blocked. If you approve, run it yourself. %s\n' "$TOOL" "$r";;
  esac
}
cc() {  # cc TOOL_NAME FIELD VALUE [CWD] -> the Claude Code hook JSON for one call
  jq -nc --arg t "$1" --arg f "$2" --arg v "$3" --arg c "${4:-$CWD}" --arg s "$SID" \
    '{hook_event_name:"PreToolUse", tool_name:$t, tool_input:{($f):$v}, cwd:$c, session_id:$s}'
}

case "$EV" in
pre)
  verdict() { local v; v=$(run "$@"); [ -n "$v" ] && deny "${v#deny?}"; return 0; }
  [ "$(get .nopath)" = true ] && deny "This $TOOL file edit names no path the kit can check, so it is blocked."
  if [ "$KIND" = shell ]; then verdict lane-guard.sh "$(cc Bash command "$GUARD_CMD" "$SHELL_CWD")"; fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    verdict tests-lock.sh "$(cc Edit file_path "$p")"
    verdict file-guard.sh "$(cc Edit file_path "$p")"
  done < <(get '.edits[]')
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    verdict file-guard.sh "$(cc Read file_path "$p")"
  done < <(get '.reads[]')
  [ "$TOOL" = opencode ] && echo '{"decision":"allow"}'   # the plugin needs an answer either way
  exit 0;;
post)
  [ "$KIND" = shell ] && cc Bash command "$CMD" "$SHELL_CWD" | "$HERE/audit-log.sh" >/dev/null 2>&1
  exit 0;;
stop)
  # Antigravity: "continue" with a reason keeps the agent working; nothing printed lets the stop go through.
  # verify-before-done.sh caps its own blocks (VERIFY_MAX_BLOCKS), so this can't loop forever.
  e=$(mktemp "${TMPDIR:-/tmp}/kitadapt.XXXXXX")
  jq -nc --arg c "$CWD" --arg s "$SID" '{hook_event_name:"Stop", cwd:$c, session_id:$s, stop_hook_active:false}' \
    | "$HERE/verify-before-done.sh" >/dev/null 2>"$e"; rc=$?
  [ "$rc" = 2 ] && jq -n --arg r "$(tail -c 4000 "$e")" '{decision:"continue",reason:$r}'
  rm -f "$e"; exit 0;;
esac
