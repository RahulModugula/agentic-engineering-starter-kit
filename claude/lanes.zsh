# Multi-session setup: a coordinator plus parallel "lanes", each in its own git worktree.
# Installed as ~/.claude/lanes.zsh. Add to your shell once:  echo 'source ~/.claude/lanes.zsh' >> ~/.zshrc
#
#   coord              the coordinator, in your main repo (plans work, merges, keeps the queue)
#   lane 1             a lane named <repo>-1 in its own worktree (does one task)
#   lane fix-login api a lane named api-fix-login in repo "api"
#   lane verifier      the reviewer: reads other lanes' PRs, never writes code
#   relane <name>      reopen a closed session with its history
#
# ---- Edit these two lines for your projects ----
REPOS=(my-app)          # every repo under $WORK that sessions may read
MAIN_REPO=my-app        # where the coordinator runs; the guard lets only this checkout merge
# ------------------------------------------------
WORK=${WORK:-$HOME/work}
# The agent CLI sessions run in: claude (default), codex, opencode or agy (Antigravity). Set it per command too:
#   LANE_TOOL=opencode lane 1        LANE_TOOL_MODEL picks that tool's model, in its own naming
# The other tools get their worktree from here ($WORK/.lanes/<repo>-<name>, branch lane-<name>) and the role as
# their first message. They can't message the coordinator: a lane tells you "ready at <sha>", you tell the
# coordinator. What each tool enforces: ~/.claude/kit/docs/OTHER-AGENTS.md.
LANE_TOOL=${LANE_TOOL:-claude}
# Per-session settings. --settings outranks a repo's own .claude/settings*.json, so a repo can't switch the
# guards off with disableAllHooks. crossSessionInbound lets the coordinator receive "ready at" from lanes.
_LANE_SETTINGS='{"crossSessionInbound":"accept","disableAllHooks":false}'

_claude_other_repos() {  # --add-dir for every repo in REPOS except $1
  local r; for r in $REPOS; do [[ $r == $1 ]] || print -r -- $WORK/$r; done
}
_lane_other() {  # _lane_other DIR ROLE OTHER_REPO...: start $LANE_TOOL in DIR, the role as its first message
  local dir=$1 role=$2; shift 2
  local msg="Read $role and follow it as your role for this session." d
  local -a m extra; [[ -n $LANE_TOOL_MODEL ]] && m=(-m $LANE_TOOL_MODEL)
  for d in "$@"; do extra+=(--add-dir $d); done
  cd $dir || return
  case $LANE_TOOL in
    codex) codex -C $dir $extra $m "$msg";;
    opencode) opencode $dir $m --prompt "$msg";;
    agy) print -r -- "Antigravity: send this as your first message: $msg"
         agy $extra ${LANE_TOOL_MODEL:+--model} ${LANE_TOOL_MODEL:+$LANE_TOOL_MODEL};;
    *) print -r -- "LANE_TOOL=$LANE_TOOL: use claude, codex, opencode or agy"; return 2;;
  esac
}
_lane_worktree() {  # _lane_worktree REPO NAME -> path of the lane's worktree (made on first use)
  local wt=$WORK/.lanes/$1-$2
  if [[ ! -d $wt ]]; then
    if git -C $WORK/$1 show-ref -q --verify refs/heads/lane-$2; then git -C $WORK/$1 worktree add -q $wt lane-$2 >&2
    else git -C $WORK/$1 worktree add -q -b lane-$2 $wt >&2; fi || return
  fi
  print -r -- $wt
}
coord() {
  if [[ $LANE_TOOL != claude ]]; then
    _lane_other $WORK/$MAIN_REPO ~/.claude/roles/coordinator.md $(_claude_other_repos $MAIN_REPO); return
  fi
  cd $WORK/$MAIN_REPO || return
  claude -n "${MAIN_REPO:l}-coordinator" --model "${COORD_MODEL:-opus}" \
    $(for d in $(_claude_other_repos $MAIN_REPO); do print -r -- --add-dir $d; done) \
    --settings "$_LANE_SETTINGS" \
    --append-system-prompt-file ~/.claude/roles/coordinator.md "$@"
}
lane() {
  local t=${1:?usage: lane <name> [repo]} repo=${2:-$MAIN_REPO}
  local role=~/.claude/roles/lane.md model=${LANE_MODEL:-sonnet}
  [[ $t == verifier ]] && { role=~/.claude/roles/verifier.md; model=${VERIFIER_MODEL:-opus}; }
  if [[ $LANE_TOOL != claude ]]; then
    local wt; wt=$(_lane_worktree $repo $t) || return
    _lane_other $wt $role $(_claude_other_repos $repo); return
  fi
  cd $WORK/$repo || return
  claude -n "${repo:l}-$t" -w "lane-$t" \
    $(for d in $(_claude_other_repos $repo); do print -r -- --add-dir $d; done) \
    --settings "$_LANE_SETTINGS" \
    --model "$model" --append-system-prompt-file "$role" "${@:3}"
}
relane() {
  case $LANE_TOOL in
    codex) cd $WORK/.lanes/${2:-$MAIN_REPO}-${1:?usage: relane <name> [repo]} && codex resume; return;;
    opencode) opencode $WORK/.lanes/${2:-$MAIN_REPO}-${1:?usage: relane <name> [repo]} --continue; return;;
    agy) print -r -- "Antigravity: reopen the conversation from inside agy."; return;;
  esac
  cd $WORK/${2:-$MAIN_REPO} || return
  claude -r "${1:?usage: relane <name> [repo]}" --settings "$_LANE_SETTINGS"
}
