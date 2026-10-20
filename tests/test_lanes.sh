#!/bin/bash
# lanes.zsh with LANE_TOOL: each agent CLI starts in the right folder (a lane gets its own worktree and branch),
# with the role as its first message; claude stays the default.
. "$(dirname "$0")/lib.sh"
command -v zsh >/dev/null || { _res 1 "zsh is not installed (needed for lanes.zsh)"; finish; exit; }
W=$TMP/work; mkdir -p "$W/app" "$W/api" "$TMP/bin"
for r in app api; do git -C "$W/$r" init -q -b main; git -c user.email=t@example.test -c user.name=t -C "$W/$r" commit -q --allow-empty -m x; done
for t in claude codex opencode agy; do  # stubs: record where they ran and with what
  printf '#!/bin/bash\n{ echo "cwd=$(pwd -P)"; for a in "$@"; do echo "arg=$a"; done; } > "%s/%s.log"\n' "$TMP" "$t" > "$TMP/bin/$t"
  chmod +x "$TMP/bin/$t"
done
run() {  # run TOOL ZSH_COMMAND -> the log of what that tool was started with
  rm -f "$TMP"/*.log
  env PATH="$TMP/bin:$PATH" WORK="$W" HOME="$TMP" LANE_TOOL="$1" zsh -fc "source '$ROOT/claude/lanes.zsh'; REPOS=(app api); MAIN_REPO=app; $2" >/dev/null 2>&1
  cat "$TMP/${1}.log" 2>/dev/null
}
real() { (cd "$1" && pwd -P); }
o=$(run claude 'lane 1'); ok "default: claude runs the lane" grep -q '^arg=-w$' <<<"$o"
o=$(run codex 'lane 1')
ok "codex: the lane gets its own worktree" test -d "$W/.lanes/app-1"
eq "codex: on its own branch" "$(git -C "$W/.lanes/app-1" rev-parse --abbrev-ref HEAD)" lane-1
ok "codex: starts in the worktree" grep -qx "cwd=$(real "$W/.lanes/app-1")" <<<"$o"
ok "codex: the role is its first message" grep -q '^arg=Read .*/.claude/roles/lane.md and follow it' <<<"$o"
ok "codex: the other repos are added" grep -qx "arg=$W/api" <<<"$o"
o=$(run codex 'lane 1'); ok "codex: a second start reuses the worktree" grep -qx "cwd=$(real "$W/.lanes/app-1")" <<<"$o"
o=$(run opencode 'lane verifier')
ok "opencode: the verifier role" grep -q '^arg=Read .*/.claude/roles/verifier.md' <<<"$o"
ok "opencode: the role goes in --prompt" grep -qx 'arg=--prompt' <<<"$o"
o=$(LANE_TOOL_MODEL=opencode/big-pickle run opencode 'lane 2')
ok "opencode: LANE_TOOL_MODEL is passed" grep -qx 'arg=opencode/big-pickle' <<<"$o"
o=$(run agy 'coord'); ok "agy: the coordinator starts in the main repo" grep -qx "cwd=$(real "$W/app")" <<<"$o"
o=$(run codex 'coord'); ok "codex: the coordinator role" grep -q 'roles/coordinator.md' <<<"$o"
eq "an unknown tool starts nothing" "$(run cursor 'lane 3')" ""
finish
