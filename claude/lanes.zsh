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
# Per-session settings. --settings outranks a repo's own .claude/settings*.json, so a repo can't switch the
# guards off with disableAllHooks. crossSessionInbound lets the coordinator receive "ready at" from lanes.
_LANE_SETTINGS='{"crossSessionInbound":"accept","disableAllHooks":false}'

_claude_other_repos() {  # --add-dir for every repo in REPOS except $1
  local r; for r in $REPOS; do [[ $r == $1 ]] || print -r -- $WORK/$r; done
}
coord() {
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
  cd $WORK/$repo || return
  claude -n "${repo:l}-$t" -w "lane-$t" \
    $(for d in $(_claude_other_repos $repo); do print -r -- --add-dir $d; done) \
    --settings "$_LANE_SETTINGS" \
    --model "$model" --append-system-prompt-file "$role" "${@:3}"
}
relane() {
  cd $WORK/${2:-$MAIN_REPO} || return
  claude -r "${1:?usage: relane <name> [repo]}" --settings "$_LANE_SETTINGS"
}
