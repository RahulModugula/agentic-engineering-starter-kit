#!/bin/bash
# Other agent CLIs: agent-adapter.sh must turn Codex, Antigravity and OpenCode hook input into the same guard
# decisions Claude Code gets (deny the real thing, allow look-alikes), answer in each tool's format, and fail closed.
# file-guard.sh must apply the kit's Read/Edit deny rules. The OpenCode plugin must throw to block.
. "$(dirname "$0")/lib.sh"
A=$ROOT/claude/hooks/agent-adapter.sh; FG=$ROOT/claude/hooks/file-guard.sh
H=$TMP/home; mkdir -p "$H/.ssh" "$H/.codex"; export HOME=$H CLAUDE_SETTINGS=$ROOT/claude/settings.json
COORD=$TMP/coord; LANE=$TMP/lane; mkdir -p "$COORD" "$LANE"
GI=(-c user.email=t@example.test -c user.name=t)
git -C "$LANE" init -q -b feature; git "${GI[@]}" -C "$LANE" commit -q --allow-empty -m x
git -C "$COORD" init -q -b main; git "${GI[@]}" -C "$COORD" commit -q --allow-empty -m x
printf "COORD_DIR=%s\nPROD_PROFILE=prod\n" "$COORD" > "$TMP/guard.conf"; export GUARD_CONF=$TMP/guard.conf
mkdir -p "$LANE/.claude" "$LANE/tests" "$LANE/src"; touch "$LANE/.claude/tests-locked"   # tests locked in the lane

# --- Codex: Claude Code's shape, its own tool names --------------------------------------------------------------
codex() {  # codex TOOL_NAME TOOL_INPUT_JSON [CWD] -> deny|allow
  local o; o=$(jq -nc --arg t "$1" --argjson i "$2" --arg c "${3:-$LANE}" '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i,cwd:$c,session_id:"s"}' | "$A" codex pre)
  [ -z "$o" ] && { echo allow; return; }
  printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecision'
}
cmd() { jq -nc --arg c "$1" '{command:$c}'; }
eq "codex: push to main is denied"                 "$(codex Bash "$(cmd 'git push origin main')")" deny
eq "codex: push of a feature branch is allowed"    "$(codex Bash "$(cmd 'git push -u origin feature')")" allow
eq "codex: a shell command as an argv array"       "$(codex Bash '{"command":["bash","-lc","git push origin main"]}')" deny
eq "codex: argv without -lc is joined"             "$(codex Bash '{"command":["git","push","origin","main"]}')" deny
eq "codex: unified exec (cmd field)"               "$(codex exec_command '{"cmd":"pkill -f job"}')" deny
eq "codex: a lane can't merge"                     "$(codex Bash "$(cmd 'gh pr merge 3 --squash')")" deny
eq "codex: the coordinator can"                    "$(codex Bash "$(cmd 'gh pr merge 3 --squash')" "$COORD")" allow
eq "codex: a harmless command"                     "$(codex Bash "$(cmd 'ls -la')")" allow
# ask has no hook answer in these tools: it becomes deny, with the reason saying the owner can run it.
eq "codex: a prod AWS write (ask) is denied"       "$(codex Bash "$(cmd 'aws s3 cp ./f s3://b/k --profile prod')")" deny
r=$(jq -nc --arg c "$LANE" '{tool_name:"Bash",tool_input:{command:"aws s3 cp ./f s3://b/k --profile prod"},cwd:$c}' | "$A" codex pre | jq -r .hookSpecificOutput.permissionDecisionReason)
ok "codex: …and says it needs your approval" grep -q "needs your approval" <<<"$r"
patch() { jq -nc --arg c "$(printf '*** Begin Patch\n*** %s File: %s\n+x\n*** End Patch\n' "$1" "$2")" '{command:$c}'; }
eq "codex: apply_patch to a locked test file"      "$(codex apply_patch "$(patch Update tests/test_a.py)")" deny
eq "codex: apply_patch adding a locked test"       "$(codex apply_patch "$(patch Add tests/test_new.py)")" deny
eq "codex: apply_patch to source is allowed"       "$(codex apply_patch "$(patch Update src/a.py)")" allow
mv_patch=$(jq -nc '{command:"*** Begin Patch\n*** Update File: src/a.py\n*** Move to: tests/test_moved.py\n*** End Patch\n"}')
eq "codex: a patch moving a file into the tests"   "$(codex apply_patch "$mv_patch")" deny
eq "codex: apply_patch run from the shell"         "$(codex Bash "$(jq -nc --arg c "$(printf "apply_patch <<'EOF'\n*** Begin Patch\n*** Update File: tests/test_a.py\n*** End Patch\nEOF")" '{command:$c}')")" deny
eq "codex: a patch to the Codex hook file"         "$(codex apply_patch "$(patch Update "$H/.codex/hooks.json")")" deny
eq "codex: a patch to the guard itself"            "$(codex apply_patch "$(patch Update "$H/.claude/hooks/lane-guard.sh")")" deny
eq "codex: input it can't read is denied"          "$(printf 'not json' | "$A" codex pre | jq -r .hookSpecificOutput.permissionDecision)" deny

# --- Antigravity: camelCase toolCall, its own tool names, {"decision":"deny"} --------------------------------------
agy() {  # agy TOOL ARGS_JSON -> deny|allow
  local o; o=$(jq -nc --arg t "$1" --argjson a "$2" --arg w "$LANE" '{toolCall:{name:$t,args:$a},workspacePaths:[$w],conversationId:"c"}' | "$A" antigravity pre)
  [ -z "$o" ] && { echo allow; return; }
  printf '%s' "$o" | jq -r .decision
}
eq "agy: push to main is denied"                   "$(agy run_command '{"CommandLine":"git push origin main"}')" deny
eq "agy: Cwd decides where it runs (coordinator)"  "$(agy run_command "$(jq -nc --arg c "$COORD" '{CommandLine:"gh pr merge 3",Cwd:$c}')")" allow
eq "agy: a lane can't merge"                       "$(agy run_command '{"CommandLine":"gh pr merge 3"}')" deny
eq "agy: a harmless command"                       "$(agy run_command '{"CommandLine":"git status"}')" allow
eq "agy: writing a locked test"                    "$(agy write_to_file '{"TargetFile":"tests/test_a.py","CodeContent":"x"}')" deny
eq "agy: editing a locked test"                    "$(agy replace_file_content '{"TargetFile":"tests/test_a.py"}')" deny
eq "agy: editing source"                           "$(agy multi_replace_file_content '{"TargetFile":"src/a.py"}')" allow
eq "agy: editing the Antigravity hook file"        "$(agy write_to_file "$(jq -nc --arg f "$H/.gemini/config/hooks.json" '{TargetFile:$f}')")" deny
eq "agy: reading an SSH key"                       "$(agy view_file "$(jq -nc --arg f "$H/.ssh/id_ed25519" '{AbsolutePath:$f}')")" deny
eq "agy: reading a normal file"                    "$(agy view_file '{"AbsolutePath":"src/a.py"}')" allow
eq "agy: input it can't read is denied"            "$(printf '{' | "$A" antigravity pre | jq -r .decision)" deny

# Stop: failing checks keep the agent working ("continue"); passing checks let it stop.
git -C "$LANE" rev-parse --show-toplevel > "$TMP/trusted"; export TRUSTED_REPOS_FILE=$TMP/trusted   # /private/var vs /var
printf '#!/bin/bash\n[ -f ok ]\n' > "$LANE/.claude/check"; chmod +x "$LANE/.claude/check"; echo change > "$LANE/src/a.py"
stopj=$(jq -nc --arg w "$LANE" '{workspacePaths:[$w],conversationId:"stop1",terminationReason:"model_stop",fullyIdle:true}')
eq "agy stop: failing checks continue the turn"    "$(printf '%s' "$stopj" | "$A" antigravity stop | jq -r .decision)" continue
touch "$LANE/ok"
eq "agy stop: passing checks let it stop"          "$(printf '%s' "$stopj" | "$A" antigravity stop)" ""
rm -f "$LANE/ok" "$LANE/src/a.py" "$LANE/.claude/check"

# post: shell commands go to the audit log, nothing is printed, a broken input never blocks.
export AUDIT_LOG=$TMP/audit.jsonl
jq -nc --arg c "$LANE" '{tool_name:"Bash",tool_input:{command:"echo hi"},cwd:$c}' | "$A" codex post >/dev/null
eq "codex post: the command is in the audit log"   "$(jq -r .command "$AUDIT_LOG" 2>/dev/null)" "echo hi"
rc 0 "post with bad input still exits 0" bash -c "printf x | '$A' codex post"
rc 2 "an unknown tool is a usage error"  bash -c "printf '{}' | '$A' cursor pre"

# A guard that crashes blocks the call (fails closed), it doesn't let it through.
mkdir -p "$TMP/broken"; cp "$A" "$TMP/broken/"; printf '#!/bin/bash\nexit 7\n' > "$TMP/broken/lane-guard.sh"; chmod +x "$TMP/broken/"*
o=$(jq -nc '{tool_name:"Bash",tool_input:{command:"ls"},cwd:"/"}' | "$TMP/broken/agent-adapter.sh" codex pre | jq -r .hookSpecificOutput.permissionDecision)
eq "a crashing guard denies"                       "$o" deny

# --- file-guard: the kit's Read/Edit deny rules -------------------------------------------------------------------
fg() {  # fg Read|Edit PATH -> deny|allow
  local o; o=$(jq -nc --arg t "$1" --arg f "$2" --arg c "$LANE" '{tool_name:$t,tool_input:{file_path:$f},cwd:$c}' | "$FG")
  [ -z "$o" ] && { echo allow; return; }
  printf '%s' "$o" | jq -r .hookSpecificOutput.permissionDecision
}
eq "file-guard: .env (bare name, relative)"        "$(fg Read .env)" deny
eq "file-guard: .env.production"                   "$(fg Read config/.env.production)" deny
eq "file-guard: .env.example is exempt (!rule)"    "$(fg Read .env.example)" allow
eq "file-guard: a .pem anywhere"                   "$(fg Read /srv/certs/site.pem)" deny
eq "file-guard: **/secrets/**"                     "$(fg Read deploy/secrets/db.txt)" deny
eq "file-guard: ~/.ssh/**"                         "$(fg Read "$H/.ssh/id_ed25519")" deny
eq "file-guard: Codex credentials"                 "$(fg Read "$H/.codex/auth.json")" deny
eq "file-guard: a normal file"                     "$(fg Read src/a.py)" allow
eq "file-guard: ~/.sshx is not ~/.ssh"             "$(fg Read "$H/.sshx/notes")" allow
ln -s "$H/.ssh/id_ed25519" "$LANE/innocent.txt"
eq "file-guard: a symlink to a secret"             "$(fg Read innocent.txt)" deny
eq "file-guard: editing the guard"                 "$(fg Edit "$H/.claude/hooks/lane-guard.sh")" deny
eq "file-guard: editing Codex's hook config"       "$(fg Edit "$H/.codex/config.toml")" deny
eq "file-guard: editing the OpenCode plugin"       "$(fg Edit "$H/.config/opencode/plugins/agentic-kit.js")" deny
eq "file-guard: editing source"                    "$(fg Edit src/a.py)" allow
eq "file-guard: Edit rules don't block reading"    "$(fg Read "$H/.claude/hooks/lane-guard.sh")" allow
eq "file-guard: no readable rules blocks"          "$(jq -nc '{tool_name:"Read",tool_input:{file_path:"a"},cwd:"/"}' | CLAUDE_SETTINGS=/nonexistent "$FG" | jq -r .hookSpecificOutput.permissionDecision)" deny
eq "file-guard: bad input blocks"                  "$(printf 'x' | "$FG" | jq -r .hookSpecificOutput.permissionDecision)" deny

# --- lane-guard: shell changes to the other tools' controls ------------------------------------------------------
eq "shell: rm the Codex hook file"                 "$(codex Bash "$(cmd 'rm ~/.codex/hooks.json')")" deny
eq "shell: sed -i the OpenCode plugin"             "$(codex Bash "$(cmd 'sed -i s/a/b/ ~/.config/opencode/plugins/agentic-kit.js')")" deny
eq "shell: overwrite the Antigravity hooks"        "$(codex Bash "$(cmd 'echo {} > ~/.gemini/config/hooks.json')")" deny
eq "shell: reading the Codex hook file is fine"    "$(codex Bash "$(cmd 'cat ~/.codex/hooks.json')")" allow

# --- review findings (2026-10-19): each of these got past the guards before the fix ------------------------------
for c in 'rm -rf ~/.codex' 'mv ~/.codex ~/x' 'rm ~/.codex/hook*' 'find ~/.codex -delete' 'rm -rf ~/.gemini' \
         'rm -rf ~/.gemini/config' 'rm -rf ~/.config/opencode' 'rm -rf ~/.config' 'echo x > ~/.config/opencode/plugin/evil.js' \
         'rm ~/.claude/kit-tools' 'rm ~/.CODEX/hooks.json' 'rm -rf ~/.Claude/hooks' 'rm ~/.claude/hook*/lane-guard.sh'; do
  eq "shell: $c" "$(codex Bash "$(cmd "$c")")" deny
done
eq "shell: listing ~/.codex is fine"               "$(codex Bash "$(cmd 'ls -la ~/.codex')")" allow
eq "shell: a project's own .config folder is fine" "$(codex Bash "$(cmd 'rm -rf build/.configure-cache')")" allow
crlf=$(jq -nc --arg f "$H/.codex/hooks.json" '{command:("*** Begin Patch\r\n*** Update File: " + $f + "\r\n+x\r\n*** End Patch\r\n")}')
eq "codex: a CRLF patch to the Codex hook file"    "$(codex apply_patch "$crlf")" deny
eq "codex: a patch header with leading spaces"     "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: src/a.py\n  *** Update File: tests/test_a.py\n*** End Patch\n"}')" deny
# workdir: where the shell command really runs. From a lane, a bare push run in the coordinator's checkout (on main).
eq "codex: workdir decides the branch a push hits" "$(codex Bash "$(jq -nc --arg w "$COORD" '{command:"git push",workdir:$w}')")" deny
eq "codex: …and a feature push from there is fine" "$(codex Bash "$(jq -nc --arg w "$COORD" '{command:"git push origin feature"}')")" allow
eq "agy: Cwd decides the branch a push hits"       "$(agy run_command "$(jq -nc --arg c "$COORD" '{CommandLine:"git push",Cwd:$c}')")" deny
# An edit with no path we can find is blocked, and edit-like tools we don't know are treated as edits.
eq "codex: Edit with a path field"                 "$(codex Edit '{"path":"tests/test_a.py"}')" deny
eq "codex: Edit with no path at all"               "$(codex Edit '{"content":"x"}')" deny
eq "agy: write_to_file with a TargetPath"          "$(agy write_to_file '{"TargetPath":"tests/test_a.py"}')" deny
eq "agy: write_to_file with no path"               "$(agy write_to_file '{"Something":"tests/test_a.py"}')" deny
eq "agy: an unknown delete tool is an edit"        "$(agy delete_file '{"TargetFile":"tests/test_a.py"}')" deny
eq "agy: reading a locked test is fine"            "$(agy view_file '{"AbsolutePath":"tests/test_a.py"}')" allow
eq "agy: grep_search over the SSH folder"          "$(agy grep_search "$(jq -nc --arg f "$H/.ssh" '{SearchPath:$f,Query:"x"}')")" deny
eq "agy: grep_search over source is fine"          "$(agy grep_search '{"SearchPath":"src","Query":"x"}')" allow
# A guard that hangs is stopped and the call blocked, children and all.
mkdir -p "$TMP/slow"; cp "$A" "$TMP/slow/"; printf '#!/bin/bash\nsleep 30\n' > "$TMP/slow/lane-guard.sh"; chmod +x "$TMP/slow/"*
t0=$(date +%s)
o=$(jq -nc '{tool_name:"Bash",tool_input:{command:"ls"},cwd:"/"}' | KIT_GUARD_TIMEOUT=1 "$TMP/slow/agent-adapter.sh" codex pre | jq -r .hookSpecificOutput.permissionDecision)
eq "a guard that hangs is denied"                  "$o" deny
ok "…within seconds, not when it finishes"         test $(( $(date +%s) - t0 )) -lt 10
# The default macOS disk ignores case, so there ~/.CODEX/hooks.json IS the Codex hook file; on Linux it isn't.
want=allow; [ "$(uname)" = Darwin ] && want=deny
eq "file-guard: capitals in a guard path ($(uname))" "$(fg Edit "$H/.CODEX/hooks.json")" "$want"
eq "file-guard: capitals in a secret ($(uname))"     "$(fg Read .ENV)" "$want"
eq "file-guard: editing kit-tools"                 "$(fg Edit "$H/.claude/kit-tools")" deny
eq "file-guard: a plugin in opencode/plugin/"      "$(fg Edit "$H/.config/opencode/plugin/evil.js")" deny
eq "file-guard: the SSH folder itself"             "$(fg Read "$H/.ssh")" deny

# --- second review (2026-10-19) -----------------------------------------------------------------------------------
# A working directory inside a protected folder, then a relative file change.
eq "opencode-shape: rm the guard via workdir"      "$(codex Bash "$(jq -nc --arg w "$H/.claude/hooks" '{command:"rm lane-guard.sh",workdir:$w}')")" deny
eq "agy: rm hooks.json with Cwd ~/.codex"          "$(agy run_command "$(jq -nc --arg w "$H/.codex" '{CommandLine:"rm hooks.json",Cwd:$w}')")" deny
eq "codex: a workdir equal to cwd changes nothing" "$(codex Bash "$(jq -nc --arg w "$LANE" '{command:"git push",workdir:$w}')")" allow
for c in 'cd ~/.codex && rm hooks.json' 'cd ~/.config/opencode && rm -rf plugins' 'cd ~/.gemini/config; rm hooks.json' \
         'pushd ~/.config/opencode/plugins; rm agentic-kit.js' 'cd ~/.codex/ && mv hooks.json h' 'rm -rf ~/.codex//' \
         'rm -rf ~/.codex/./' 'rm -rf ~/.config/opencode/../opencode' 'rm -rf ~/.gemini/config/../config' 'rm -rf ~/.cod*' \
         'rm -rf ~/.gem*' 'rm -rf ~/.c*' 'rm -rf ~/.config/op*' 'rm -rf ~/.conf*/opencode' 'rm -rf ~/.cla*' \
         'cd ~/.claude && find . -delete' 'find ~/.codex -name "*.json" -delete'; do
  eq "shell: $c" "$(codex Bash "$(cmd "$c")")" deny
done
# Ordinary read-only work in busy folders stays allowed.
for c in 'find ~/.config -name "*.json"' 'find ~/.codex -name "*.jsonl" -mtime +30' 'cp .config/app.yml dist/' \
         'git checkout -- .config' 'ls ~/.cache/*' 'cat ~/.config/git/config'; do
  eq "shell (allowed): $c" "$(codex Bash "$(cmd "$c")")" allow
done
# Antigravity: tools that create other things aren't file edits; every path-like argument is checked.
eq "agy: an MCP create_issue tool is not an edit"  "$(agy mcp_github_create_issue '{"title":"x"}')" allow
eq "agy: create_memory is not an edit"             "$(agy create_memory '{"Content":"x"}')" allow
eq "agy: a second path argument is checked"        "$(agy rename_file "$(jq -nc --arg f "$H/.codex/hooks.json" '{TargetFile:"src/a.py",NewPath:$f}')")" deny
eq "codex: a second path field is checked"         "$(codex Edit '{"file_path":"src/a.py","path":"tests/test_a.py"}')" deny
eq "agy: a literal ~ path to a secret"             "$(agy view_file '{"AbsolutePath":"~/.ssh/id_rsa"}')" deny
# One time budget per call: a patch with many files past it is blocked, not left to the tool's own timeout.
many=$(jq -nc '{command:("*** Begin Patch\n" + ([range(40)] | map("*** Update File: src/f\(.).py\n") | join("")) + "*** End Patch\n")}')
o=$(jq -nc --argjson i "$many" --arg c "$LANE" '{tool_name:"apply_patch",tool_input:$i,cwd:$c}' | KIT_GUARD_TIMEOUT=1 "$A" codex pre | jq -r .hookSpecificOutput.permissionDecisionReason)
ok "a call past its time budget is denied, and says why" grep -q "took longer than 1s" <<<"$o"
eq "KIT_GUARD_TIMEOUT=0 doesn't switch the limit off" "$(jq -nc '{tool_name:"Bash",tool_input:{command:"ls"},cwd:"/"}' | KIT_GUARD_TIMEOUT=0 "$TMP/slow/agent-adapter.sh" codex pre | jq -r .hookSpecificOutput.permissionDecision)" deny

# --- OpenCode: the plugin calls the adapter and throws to block ----------------------------------------------------
if command -v node >/dev/null 2>&1; then
  cat > "$TMP/oc.mjs" <<'EOF'
const { AgenticKit } = await import(process.argv[2])
const [tool, args] = [process.argv[3], JSON.parse(process.argv[4])]
const hooks = await AgenticKit({ directory: process.argv[5] })
try { await hooks["tool.execute.before"]({ tool, sessionID: "s", callID: "c1" }, { args }); console.log("allow") }
catch (e) { console.log("deny") }
EOF
  oc() { KIT_ADAPTER=${KA:-$A} node "$TMP/oc.mjs" "$ROOT/tools/opencode/agentic-kit.js" "$1" "$2" "$LANE"; }
  eq "opencode: push to main"                      "$(oc bash '{"command":"git push origin main"}')" deny
  eq "opencode: a harmless command"                "$(oc bash '{"command":"ls"}')" allow
  eq "opencode: editing a locked test"             "$(oc edit '{"filePath":"tests/test_a.py"}')" deny
  eq "opencode: editing source"                    "$(oc write '{"filePath":"src/a.py"}')" allow
  eq "opencode: reading .env"                      "$(oc read '{"filePath":".env"}')" deny
  eq "opencode: a patch to a locked test"          "$(oc patch "$(jq -nc '{patchText:"*** Begin Patch\n*** Update File: tests/test_a.py\n*** End Patch"}')")" deny
  eq "opencode: edit with a path field"            "$(oc edit '{"path":"tests/test_a.py"}')" deny
  eq "opencode: grep in .env"                      "$(oc grep '{"pattern":"KEY","path":".env"}')" deny
  eq "opencode: workdir decides the branch"        "$(oc bash "$(jq -nc --arg w "$COORD" '{command:"git push",workdir:$w}')")" deny
  eq "opencode: no guard means blocked"            "$(KA=/nonexistent/agent-adapter.sh oc bash '{"command":"ls"}')" deny
  exports=$(node -e 'import(process.argv[1]).then(m => console.log(Object.keys(m).join(",")))' "$ROOT/tools/opencode/agentic-kit.js")
  eq "opencode: the plugin exports only the plugin" "$exports" AgenticKit
else
  _res 1 "node is not installed, so the OpenCode plugin can't be tested (install node)"
fi
finish
