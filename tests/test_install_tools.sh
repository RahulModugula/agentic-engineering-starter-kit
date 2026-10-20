#!/bin/bash
# install.sh --tool: Codex, OpenCode and Antigravity get the kit's hooks and rules MERGED into what you already
# have; the dry run changes nothing; status detects drift; rollback restores the whole home byte-for-byte.
. "$(dirname "$0")/lib.sh"
H=$TMP/home; CH=$H/.claude
export CLAUDE_HOME=$CH INSTALL_BACKUPS=$H/.claude-backups MERGE_STATE=$TMP/ms KIT_SETTINGS=$ROOT/claude/settings.json
mkdir -p "$CH" "$H/.codex" "$H/.gemini/config" "$H/.config/opencode"
mkdir -p "$TMP/fb"; printf '#!/bin/bash\necho "2.1.295 (Claude Code)"\n' > "$TMP/fb/claude"; chmod +x "$TMP/fb/claude"
export PATH="$TMP/fb:$PATH"
# What you had before: your own Codex hook and rules, your own Antigravity hook. OpenCode has no rules yet.
cat > "$H/.codex/hooks.json" <<'EOF'
{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "~/my-codex-stop.sh"}]}]}}
EOF
printf 'My Codex rules.\n' > "$H/.codex/AGENTS.md"
echo '{"my-hook": {"Stop": [{"type": "command", "command": "./mine.sh"}]}}' > "$H/.gemini/config/hooks.json"
snap() { (cd "$H" && find . \( -type f -o -type l \) ! -path './.claude-backups/*' | sort | while read -r f; do
  if [ -L "$f" ]; then echo "link $f $(readlink "$f")"; else echo "file $f $(shasum < "$f")"; fi; done) > "$1"; }
snap "$TMP/before"
I=$ROOT/install.sh; ALL=(--tool codex,opencode,antigravity)

out=$(/bin/bash "$I" "${ALL[@]}")
ok "dry run names the tools"                 grep -q "Agent CLIs besides Claude Code: codex opencode antigravity" <<<"$out"
ok "dry run shows the Codex hook merge"      grep -q "~ MERGE @/.codex/hooks.json" <<<"$out"
ok "dry run shows the Codex rules block"     grep -q "~ RULES @/.codex/AGENTS.md" <<<"$out"
ok "dry run shows the OpenCode plugin link"  grep -q "+ LINK  @/.config/opencode/plugins/agentic-kit.js" <<<"$out"
snap "$TMP/after-dry"; ok "dry run changed nothing" cmp -s "$TMP/before" "$TMP/after-dry"
eq "no tools by default here (KIT_TOOLS=none)" "$(/bin/bash "$I" | grep -c '@/')" 0
rc 2 "an unknown tool is refused"            /bin/bash "$I" --tool cursor
rc 2 "--tool without a value is refused"     /bin/bash "$I" --apply --tool

/bin/bash "$I" --apply "${ALL[@]}" > "$TMP/apply.out" 2>&1
ok "apply ends with status OK"               grep -q "STATUS OK.*also set up: codex opencode antigravity" "$TMP/apply.out"
ok "apply says Codex needs /hooks review"    grep -q "run /hooks once" "$TMP/apply.out"
C=$H/.codex/hooks.json
ok "your Codex hook is kept"                 jq -e '[.hooks.Stop[].hooks[].command] | index("~/my-codex-stop.sh")' "$C"
eq "Codex gets the guard, path written out and quoted" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$C")" "'$CH/hooks'/agent-adapter.sh codex pre"
ok "Codex gets the checks-must-pass stop"    jq -e --arg c "'$CH/hooks'/verify-before-done.sh" '[.hooks.Stop[].hooks[].command] | index($c)' "$C"
# Run as a shell would: unreadable input must come back as a deny, which proves the command started.
started() { bash -c "$1" < /dev/null 2>/dev/null | grep -q deny; }
ok "the Codex guard command runs from a shell"       started "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$C")"
ok "your Codex rules are kept"               grep -q "My Codex rules." "$H/.codex/AGENTS.md"
ok "Codex rules get the kit's rules"         grep -q "Never print, paste or commit secrets" "$H/.codex/AGENTS.md"
G=$H/.gemini/config/hooks.json
eq "your Antigravity hook is kept"           "$(jq -r '.["my-hook"].Stop[0].command' "$G")" ./mine.sh
eq "Antigravity gets the guard"              "$(jq -r '.["agentic-kit"].PreToolUse[0].hooks[0].command' "$G")" "'$CH/hooks'/agent-adapter.sh antigravity pre"
ok "the Antigravity guard command runs from a shell" started "$(jq -r '.["agentic-kit"].PreToolUse[0].hooks[0].command' "$G")"
eq "Antigravity rules are a link (you had none)" "$(readlink "$H/.gemini/AGENTS.md")" "$ROOT/claude/CLAUDE.md"
eq "the OpenCode plugin is a link"           "$(readlink "$H/.config/opencode/plugins/agentic-kit.js")" "$ROOT/tools/opencode/agentic-kit.js"
eq "OpenCode rules are a link"               "$(readlink "$H/.config/opencode/AGENTS.md")" "$ROOT/claude/CLAUDE.md"
ok "status OK (reads the tools from kit-tools)" /bin/bash "$I" --status
ok "dry run after apply: nothing to change"  grep -q "^0 change(s) would be made" <<<"$(/bin/bash "$I" "${ALL[@]}")"

/bin/bash "$I" --apply "${ALL[@]}" >/dev/null
eq "a second apply adds no second rules block" "$(grep -c 'agentic-kit rules: install.sh' "$H/.codex/AGENTS.md")" 1
eq "a second apply adds no duplicate Codex hook" "$(jq '[.hooks.PreToolUse[].hooks[].command] | length' "$C")" 1
/bin/bash "$I" --rollback >/dev/null

# Your text after the kit's rules block stays after it, and status stays OK.
printf '\nMy closing note.\n' >> "$H/.codex/AGENTS.md"
ok "text after the rules block: status still OK" /bin/bash "$I" --status
/bin/bash "$I" --apply "${ALL[@]}" >/dev/null
eq "…and a re-apply keeps it last" "$(tail -n 1 "$H/.codex/AGENTS.md")" "My closing note."
/bin/bash "$I" --rollback >/dev/null

# Drift: each piece a later edit could lose is reported.
cp "$C" "$TMP/c.json"; jq '.hooks.PreToolUse = []' "$TMP/c.json" > "$C"
no "status detects the Codex guard removed" /bin/bash "$I" --status
cp "$TMP/c.json" "$C"
cp "$G" "$TMP/g.json"; jq 'del(.["agentic-kit"])' "$TMP/g.json" > "$G"
no "status detects the Antigravity hooks removed" /bin/bash "$I" --status
cp "$TMP/g.json" "$G"
rm "$H/.config/opencode/plugins/agentic-kit.js"
no "status detects the OpenCode plugin missing" /bin/bash "$I" --status
ln -s "$ROOT/tools/opencode/agentic-kit.js" "$H/.config/opencode/plugins/agentic-kit.js"
cp "$H/.codex/AGENTS.md" "$TMP/a.md"; printf 'My Codex rules.\n' > "$H/.codex/AGENTS.md"
no "status detects the Codex rules block removed" /bin/bash "$I" --status
cp "$TMP/a.md" "$H/.codex/AGENTS.md"
ok "status OK again once repaired" /bin/bash "$I" --status

/bin/bash "$I" --rollback >/dev/null
snap "$TMP/after-rb"
ok "rollback restores the whole home byte-for-byte" cmp -s "$TMP/before" "$TMP/after-rb"
no "rollback removes the plugins folder it made" test -e "$H/.config/opencode/plugins"
no "rollback removes kit-tools" test -e "$CH/kit-tools"

# A home with a space (and a quote) in its name: the hook commands still start.
SP="$TMP/my o'home"; mkdir -p "$SP/.claude"
CLAUDE_HOME="$SP/.claude" INSTALL_BACKUPS="$SP/.claude-backups" /bin/bash "$I" --apply --tool codex,antigravity >/dev/null 2>&1
ok "space and quote in the home: Codex guard starts" started "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SP/.codex/hooks.json")"
ok "space and quote in the home: Antigravity guard starts" started "$(jq -r '.["agentic-kit"].PreToolUse[0].hooks[0].command' "$SP/.gemini/config/hooks.json")"

# A hook file we can't parse is never overwritten, and nothing else changes either.
echo '{oops' > "$C"
rc 1 "apply refuses an unparseable Codex hook file" /bin/bash "$I" --apply --tool codex
eq "the unparseable file is untouched" "$(cat "$C")" '{oops'
no "the refused apply linked nothing" test -e "$CH/kit"
finish
