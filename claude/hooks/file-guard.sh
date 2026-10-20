#!/bin/bash
# PreToolUse(Read|Edit|Write) for agent CLIs that don't have Claude Code's permission rules (Codex, OpenCode,
# Antigravity; agent-adapter.sh calls it). It applies the same Read(...) and Edit(...) deny rules Claude Code
# enforces, read from your ~/.claude/settings.json (CLAUDE_SETTINGS overrides; the kit's own copy if yours is
# missing): secrets stay unread, and the guards' own files stay unedited. Edit rules cover Edit and Write.
# Patterns: `~/x` is under your home, a pattern with a `/` matches anywhere in the path (`**/secrets/**`), a bare
# name matches the file name (`.env`, `*.pem`), and `!pattern` exempts. A symlink is checked as itself and as its
# target, a folder as what is inside it, and on macOS without regard to case. It FAILS CLOSED: no jq/python3, bad input or no readable rules blocks the call.
deny() { jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null \
  || echo "file-guard: $1" >&2; [ -n "$2" ] && exit "$2"; exit 0; }
command -v jq >/dev/null 2>&1 || deny "jq is not installed, so the file guard can't read the call. Install jq." 2
command -v python3 >/dev/null 2>&1 || deny "python3 is not installed, so the file guard can't check paths." 2
IN=$(cat)
TOOL=$(printf '%s' "$IN" | jq -er '.tool_name // ""' 2>/dev/null) || deny "couldn't parse the tool input (file-guard)."
F=$(printf '%s' "$IN" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')
CWD=$(printf '%s' "$IN" | jq -r '.cwd // ""')
[ -n "$F" ] || exit 0
case "$TOOL" in Read) KIND=Read;; Edit|Write|NotebookEdit|MultiEdit) KIND=Edit;; *) exit 0;; esac
S=${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
jq -e . "$S" >/dev/null 2>&1 || S=$HOME/.claude/kit/claude/settings.json
RULES=$(jq -r --arg k "$KIND" '.permissions.deny[]? | select(startswith($k + "(") and endswith(")")) | .[($k|length)+1:-1]' "$S" 2>/dev/null) \
  || deny "couldn't read the deny rules from $S (file-guard)."
R=$(KIND=$KIND RULES=$RULES python3 -I -c '
import os, re, sys
homes = {os.path.normpath(os.path.expanduser("~")), os.path.realpath(os.path.expanduser("~"))}
def rx(p):
    out, i = "", 0
    while i < len(p):
        if p.startswith("**/", i): out += "(?:.*/)?"; i += 3
        elif p.startswith("**", i): out += ".*"; i += 2
        elif p[i] == "*": out += "[^/]*"; i += 1
        elif p[i] == "?": out += "[^/]"; i += 1
        else: out += re.escape(p[i]); i += 1
    return out
CI = re.I if sys.platform == "darwin" else 0   # the default macOS disk ignores case: ~/.CODEX is ~/.codex
def hit(pat, path):
    if pat.startswith("~/"): return any(hit(h + pat[1:], path) for h in homes)
    if pat.startswith("/"): return re.fullmatch(rx(pat), path, CI) is not None
    if "/" in pat: return re.fullmatch("(?:.*/)?" + rx(pat), path, CI) is not None
    return re.fullmatch(rx(pat), os.path.basename(path), CI) is not None
f, cwd = sys.argv[1], sys.argv[2]
f = os.path.expanduser(f)   # a tool may pass ~/.ssh/id_rsa as it is
if not os.path.isabs(f): f = os.path.join(cwd or os.getcwd(), f)
paths = {os.path.normpath(f), os.path.realpath(f)}
# A folder (the path of a search or a listing) is checked as what is inside it: ~/.ssh stands for ~/.ssh/**.
paths |= {p + "/.kit-probe" for p in paths if os.path.isdir(p)}
rules = [r for r in os.environ["RULES"].splitlines() if r]
allow = [r[1:] for r in rules if r.startswith("!")]
for p in paths:
    for r in rules:
        if not r.startswith("!") and hit(r, p) and not any(hit(a, p) for a in allow):
            print(r); sys.exit(0)
' "$F" "$CWD") || deny "the file guard couldn't check $F."
[ -z "$R" ] && exit 0
if [ "$KIND" = Read ]; then deny "Reading $F is blocked by the kit's rule Read($R): it can hold secrets (file-guard)."
else deny "Changing $F is blocked by the kit's rule Edit($R): it's one of the guards' own controls. Owner-only (file-guard)."; fi
