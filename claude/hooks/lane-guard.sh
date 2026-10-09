#!/bin/bash
# PreToolUse(Bash) guard for the multi-lane setup. It parses the command into simple commands (after `;` `&&` `||`
# `|` `(` `)` and newlines), looks through wrappers and shell keywords to the program each one runs, and checks
# that program's arguments. Rules:
#  - DENY  a push whose target is main/master, or a bare `git push` while on main/master.
#  - DENY  any force push (--force-with-lease on your own branch is allowed).
#  - DENY  merges (`gh pr merge`, a merge via `gh api`, merge/release scripts) outside the coordinator's checkout.
#  - DENY  `pkill` / `killall`: they stop processes by pattern, including other sessions' jobs. Stop yours by PID.
#  - DENY  sessions recording human approvals, or setting/lifting the test lock (owner-only, via `!` lines).
#  - ASK   AWS writes against the prod profile (only when PROD_PROFILE is set in guard.conf).
# Limits (see docs/ARCHITECTURE.md): this is a guard against mistakes and laundering between sessions, not a sandbox.
# A process running as you can still edit files directly; server-side rules are the hard boundary.
HERE=$(cd "$(dirname "$0")" && pwd)
CONF=${GUARD_CONF:-$HOME/.claude/guard.conf}
COORD_DIR=""; PROD_PROFILE=""; COORD_SCRIPTS_EXTRA=""
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"
COORD_SCRIPTS="merge-guard|merge-queue|merge-batch${COORD_SCRIPTS_EXTRA:+|$COORD_SCRIPTS_EXTRA}"

IN=$(cat)
RAW=$(printf '%s' "$IN" | jq -r '.tool_input.command // ""')
CWD=$(printf '%s' "$IN" | jq -r '.cwd // ""')
# Heredoc bodies are data (a doc that mentions `git push origin main` is fine)... unless the heredoc is fed to a
# shell or interpreter, in which case its body IS commands, so it is checked too.
SHELLS='bash|sh|zsh|dash|ksh|source|python3?|perl|ruby|node'
PIPED=0   # text piped into a shell is commands: then echo/printf arguments are parsed as commands too
printf '%s' "$RAW" | grep -Eq "\\|[[:space:]]*(/[^[:space:]]*/)?($SHELLS)([[:space:]]|\$)" && PIPED=1
if [ "$PIPED" = 1 ] || printf '%s' "$RAW" | grep -Eq "(^|[^[:alnum:]_./-])($SHELLS)([[:space:]][^|;&]*)?<<|(^|[^[:alnum:]_])eval([[:space:]]|\$)"; then
  SRC=$RAW
else
  SRC=$(printf '%s' "$RAW" | awk -f "$HERE/lib-strip-heredoc.awk")
fi
# Quotes and backslashes become spaces, so `"main"` and `sh -c '… main'` parse like bare words.
SRC=$(printf '%s' "$SRC" | tr "\"'\\\\" '   ')

out() { jq -n --arg d "$1" --arg r "$2" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'; exit 0; }

# simple_cmds -> one line per simple command: the program's basename, then its arguments. Wrappers and keywords
# are skipped: VAR=val, env, nohup, exec, command, builtin, time, sudo, caffeinate, nice, timeout N, xargs [opts],
# bash/sh/zsh/source/. [opts], and { } ! if then else elif do while until fi done.
simple_cmds() {
  set -f
  printf '%s\n' "$SRC" | tr ';&|()`\n' '\n\n\n\n\n\n\n' | while read -r line; do
    # shellcheck disable=SC2086
    set -- $line
    while [ $# -gt 0 ]; do
      case "$1" in
        '{'|'}'|'!'|if|then|else|elif|do|while|until|fi|done|eval) shift;;
        watch) shift; while [ $# -gt 0 ]; do case "$1" in -n|-d|--interval) shift 2;; -*) shift;; *) break;; esac; done;;
        stdbuf|unbuffer|chronic) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done;;
        flock) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done; shift;;      # flock [opts] FILE cmd
        script) shift; while [ $# -gt 0 ]; do case "$1" in -c) shift; break;; -*) shift;; *) shift; break;; esac; done;;
        ssh) shift; while [ $# -gt 0 ]; do case "$1" in -[bcDEeFIiJLlmOopQRSWw]) shift 2;; -*) shift;; *) shift; break;; esac; done;;
        parallel) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done;;
        echo|printf) if [ "$PIPED" = 1 ]; then shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done; else break; fi;;
        *=*) case "$1" in -*) break;; esac; shift;;
        env) shift; while [ $# -gt 0 ]; do case "$1" in -u|-S|-C) shift 2;; -*|*=*) shift;; *) break;; esac; done;;
        nohup|exec|command|builtin|time|sudo|caffeinate) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done;;
        nice) shift; [ "${1:-}" = -n ] && shift 2; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done;;
        timeout) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done; shift;;
        xargs) shift; while [ $# -gt 0 ]; do case "$1" in -I|-n|-L|-P|-s|-E|-d) shift 2;; -*) shift;; *) break;; esac; done;;
        bash|sh|zsh|dash|ksh|/bin/bash|/bin/sh|/bin/zsh|source|.) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done;;
        *) break;;
      esac
    done
    [ $# -gt 0 ] || continue
    p=${1##*/}; shift
    printf '%s %s\n' "$p" "$*"
  done
  set +f
}
CMDS=$(simple_cmds)
# Message text (commit messages, PR titles/bodies) is data, not a command or a path: drop it before matching.
CMDS=$(printf '%s\n' "$CMDS" | sed -E \
  -e '/^git /s/[[:space:]](-m|--message|-F|--file)([[:space:]=].*)?$//' \
  -e '/^gh /s/[[:space:]](-b|--body|-t|--title|-F|--body-file)([[:space:]=].*)?$//')
PROGS=$(printf '%s\n' "$CMDS" | awk 'NF{print $1}')
runs() { printf '%s\n' "$PROGS" | grep -Eq "^($1)$"; }
in_coord() { [ -n "$COORD_DIR" ] && [ "$CWD" = "$COORD_DIR" ]; }
# Programs that can create, change or delete a file (git only via rm/mv/clean/checkout/restore).
MUTATORS='rm|rmdir|unlink|shred|mv|cp|ln|tee|truncate|touch|chmod|chown|find|dd|install|rsync|sed|perl|python|python3|awk|node|ruby'

# A protected file touched by a file-changing command (by name, or by a glob that could match it), or a redirect.
touches() {
  printf '%s\n' "$CMDS" | grep -E "^($MUTATORS)( |$)|^git( .*)? (rm|mv|clean|checkout|restore)( |$)" | grep -Eq -- "$1" && return 0
  # An interpreter one-liner (python -c, perl -e, …) is split apart by shell parsing; if one runs, the whole command
  # text counts.
  runs 'python|python3|perl|ruby|node|awk' && printf '%s' "$SRC" | grep -Eq -- "$1" && return 0
  printf '%s' "$SRC" | grep -Eq -- ">[[:space:]]*[^[:space:]]*($1)"
}

# --- merges: coordinator only ---------------------------------------------------------------------------------
if runs "($COORD_SCRIPTS)\.sh"; then
  in_coord || out deny "Merge/release scripts are coordinator-only (lane-guard). Report 'ready at <full sha>' to the coordinator."
fi
gh_merge() {  # any `gh … pr … merge …` (global flags anywhere), or a merge through `gh api` (REST or GraphQL)
  local g; g=$(printf '%s\n' "$CMDS" | awk '$1=="gh"' | grep -Ev '[[:space:]](--help|-h)([[:space:]]|$)')
  printf '%s\n' "$g" | grep -Eq '(^|[[:space:]])pr([[:space:]].*)?[[:space:]]merge([[:space:]]|$)' && return 0
  printf '%s\n' "$g" | grep -Eq '(^|[[:space:]])api([[:space:]]|$).*(/merge([[:space:]?]|$)|/merges([[:space:]?]|$))' && return 0
  printf '%s\n' "$g" | grep -Eq '(^|[[:space:]])api([[:space:]]|$).*(mergePullRequest|enablePullRequestAutoMerge|mergeBranch)'
}
if gh_merge; then
  in_coord || out deny "Lanes never merge (lane-guard). Report 'ready at <full sha>' to the coordinator."
fi

# --- owner-only records --------------------------------------------------------------------------------------
# Running human-approve.sh (any spelling, incl. globs) or changing its record is owner-only.
runs 'human-approve\.sh|human-a[^ ]*[*?[][^ ]*' \
  && out deny "Only a person records a human review, with a '!' line in the pane (lane-guard)."
touches 'human-approved|human-a[^ ]*[*?[]|merge-queue/[*?[]|merge-queue/?$' \
  && out deny "The human-review record is owner-only (lane-guard)."
runs 'tests-lock\.sh|tests-l[^ ]*[*?[][^ ]*' && out deny "Only the owner locks or unlocks tests, with a '!' line in the pane (lane-guard)."
touches 'tests-lock|\.claude/[*?[]|\.claude/te[*?[]|(^|[[:space:]/])\.claude/?([[:space:]]|$)' \
  && out deny "The test lock is owner-only (lane-guard)."
if [ "${GOS_PROTECT:-0}" = 1 ]; then   # change 4, off by default
  runs 'go\.sh' && out deny "Only the owner records a go, with a '!' line in the pane (lane-guard)."
  touches '\.claude/gos' && out deny "The go directory is owner-only (lane-guard)."
fi

# --- pattern kills -----------------------------------------------------------------------------------------------
runs 'pkill|killall' && out deny "pkill/killall match by pattern and can stop other sessions' jobs (lane-guard). Stop your own process by its PID, or use stop_own from ~/.claude/lib/opslib.sh."

# --- git push --------------------------------------------------------------------------------------------------
printf '%s\n' "$CMDS" | awk '$1=="git"' | while read -r _ rest; do
  set -f
  # shellcheck disable=SC2086
  set -- $rest
  D=$CWD
  while [ $# -gt 0 ]; do   # git's global options come before the subcommand
    case "$1" in
      -C) D=$2; shift 2;;
      -c) case "${2:-}" in alias.*) echo "ALIAS";; esac; shift 2;;      # inline aliases could hide a push
      -calias.*) echo "ALIAS"; shift;;
      --git-dir=*|--work-tree=*|--namespace=*|-c*|--no-pager|-p|--paginate|--bare) shift;;
      --git-dir|--work-tree|--namespace) shift 2;; *) break;;
    esac
  done
  [ "${1:-}" = push ] || continue
  shift
  # The branch a "HEAD"/"@" refspec means. symbolic-ref also works on an unborn branch (a brand-new repo).
  CUR=$(git -C "$D" symbolic-ref --short -q HEAD 2>/dev/null)
  npos=0
  for a in "$@"; do
    case "$a" in
      --force-with-lease*|--force-if-includes) ;;
      --force|--force=*) echo "FORCE"; break;;
      --all|--mirror|--branches) echo "MAIN"; break;;   # pushes every branch, main included
      --*) ;;
      -*f*) echo "FORCE"; break;;           # -f, -uf, -fu…: any short-flag cluster with f
      +*) echo "FORCE"; break;;             # +refspec
      -*) ;;
      *) npos=$((npos + 1))
         [ "$npos" -ge 2 ] || continue      # the first positional is the remote
         dst=${a#*:}; dst=${dst#refs/heads/}
         case "$dst" in HEAD|@|'') dst=$CUR;; esac
         case "$dst" in main|master) echo "MAIN"; break;; esac;;
    esac
  done
  if [ "$npos" -lt 2 ]; then
    case "$CUR" in main|master) echo "BAREMAIN $CUR";; esac
  fi
  set +f
done > "${TMPDIR:-/tmp}/laneguard.$$" 2>/dev/null
PUSH=$(cat "${TMPDIR:-/tmp}/laneguard.$$" 2>/dev/null); rm -f "${TMPDIR:-/tmp}/laneguard.$$"
case "$PUSH" in
  *ALIAS*) out deny "Inline git aliases (git -c alias.…) are blocked: they can hide a push (lane-guard).";;
  *FORCE*) out deny "Force push is blocked (lane-guard). Use --force-with-lease on your own feature branch only.";;
  *BAREMAIN*) out deny "You are on main/master; a bare push would update it (lane-guard). Create a feature branch first.";;
  *MAIN*) out deny "Pushing to main/master is blocked (lane-guard). Push a feature branch and report 'ready at <sha>' to the coordinator.";;
esac

# --- prod AWS writes: ask ----------------------------------------------------------------------------------------
if [ -n "$PROD_PROFILE" ] && runs aws && printf '%s' "$SRC" | grep -Eq -- "--profile[=[:space:]]+$PROD_PROFILE([[:space:]]|\$)|AWS_PROFILE=$PROD_PROFILE([[:space:]]|\$)|export-credentials[^;&|]*$PROD_PROFILE"; then
  if printf '%s\n' "$CMDS" | awk '$1=="aws"' | grep -Eq '^aws[[:space:]]+[a-z0-9-]+[[:space:]]+(create|update|delete|put|deploy|attach|detach|tag|untag|run-task|start|stop|invoke|set|modify|register|deregister|remove|add|rm|execute|send|publish|restore|reset|enable|disable)[a-z-]*([[:space:]]|$)'; then
    out ask "Prod AWS write (lane-guard). Approve only if the owner's go for exactly this is in this pane."
  fi
  printf '%s\n' "$CMDS" | awk '$1=="aws"' | grep -Eq '^aws[[:space:]]+s3[[:space:]]+(cp|mv|sync)[[:space:]].*[[:space:]]s3://[^[:space:]]*([[:space:]]+--.*)?$' \
    && out ask "Prod S3 write (lane-guard). Approve only if the owner's go for exactly this is in this pane."
fi
exit 0
