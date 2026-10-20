#!/bin/bash
# PreToolUse(Bash) guard for the multi-session setup. It parses the command into simple commands (split on `;`
# `&` `|` `(` `)` and newlines), looks through wrappers and shell keywords to the program each one runs, and checks
# that program's arguments. Rules:
#  - DENY  a push that could update main/master (named, HEAD/@ on main, glob or matching refspecs, --all/--mirror,
#          a bare push on main, push settings via `git -c`/`git config`), and any force push (--force-with-lease ok).
#  - DENY  merges (`gh pr merge`, merges via `gh api`/curl/wget, merge scripts) outside the coordinator's checkout.
#  - DENY  `pkill` / `killall` (pattern kills hit other sessions' jobs), and a variable used as the command name.
#  - DENY  file-changing commands aimed at the controls: ~/.claude hooks/lib/kit/settings/guard.conf/trust list,
#          the merge-queue state (approvals, verified records, queue), and the test lock.
#  - ASK   AWS writes with the prod profile (PROD_PROFILE in guard.conf): anything but read-only verbs.
# It FAILS CLOSED: if it can't read the command (no jq, bad JSON), it blocks. Limits: it parses shell, it doesn't run
# it, and every session runs as you; see docs/ARCHITECTURE.md. Server-side rules are the hard boundary.
deny_hard() { echo "lane-guard: $1" >&2; exit 2; }   # exit 2 = block (used when we can't even build JSON)
command -v jq >/dev/null 2>&1 || deny_hard "jq is not installed, so the guard can't read the command. Install jq."
HERE=$(cd "$(dirname "$0")" && pwd)
CONF=${GUARD_CONF:-$HOME/.claude/guard.conf}
COORD_DIR=""; PROD_PROFILE=""; COORD_SCRIPTS_EXTRA=""
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"
COORD_SCRIPTS="merge-guard|merge-queue|merge-batch${COORD_SCRIPTS_EXTRA:+|$COORD_SCRIPTS_EXTRA}"

IN=$(cat)
RAW=$(printf '%s' "$IN" | jq -er '.tool_input.command // ""' 2>/dev/null) || deny_hard "couldn't parse the tool input."
CWD=$(printf '%s' "$IN" | jq -r '.cwd // ""' 2>/dev/null)

# Message text (commit/tag messages, PR/issue titles and bodies) is data: drop quoted values of those flags first,
# so `;`, `(` or words like "merge" inside a message don't parse as commands.
RAW=$(printf '%s' "$RAW" | perl -0pe 's/((?:^|\s)(?:-m|--message|--body|--title|--notes))(\s+|=)("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/$1 MSG/g')

# Fast path: nothing that could matter -> allow without parsing (keeps the guard cheap on every Bash call).
Q=$(printf '%s' "$RAW" | tr -d "\"'\\\\")
printf '%s' "$Q" | grep -Eiq "push|merge|kill|aws|refs|Ref|\.claude|\.codex|opencode|\.gemini|\.config|/\.[^/[:space:]]*[*?[]|human|tests-l|<<|eval|[\$\`|]|curl|wget|config|go\.sh|$COORD_SCRIPTS" || exit 0

SHELLS='bash|sh|zsh|dash|ksh|source|python3?|perl|ruby|node'
PIPED=0   # text piped into a shell is commands: then echo/printf arguments are parsed as commands too
printf '%s' "$RAW" | grep -Eq "\\|[[:space:]]*(/[^[:space:]]*/)?($SHELLS)([[:space:]]|\$)" && PIPED=1
if [ "$PIPED" = 1 ] || printf '%s' "$RAW" | grep -Eq "(^|[^[:alnum:]_./-])($SHELLS)([[:space:]][^|;&]*)?<<|(^|[^[:alnum:]_])eval([[:space:]]|\$)"; then
  SRC=$RAW        # a heredoc fed to a shell: its body is commands, keep it
else
  SRC=$(printf '%s' "$RAW" | awk -f "$HERE/lib-strip-heredoc.awk")
fi
# Quotes and backslashes are deleted (not turned into spaces), so `ma''in`, `pu""sh` and `human-a\pproved` rejoin.
SRC=$(printf '%s' "$SRC" | tr -d "\"'\\\\")

out() { jq -n --arg d "$1" --arg r "$2" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'; exit 0; }

# simple_cmds -> one line per simple command: the program's basename, then its arguments, after wrappers
# (matched by basename, so /usr/bin/env etc. count) and shell keywords.
simple_cmds() {
  set -f
  printf '%s\n' "$SRC" | tr ';&|()`\n' '\n\n\n\n\n\n\n' | while read -r line; do
    # shellcheck disable=SC2086
    set -- $line
    while [ $# -gt 0 ]; do
      case "${1##*/}" in
        '{'|'}'|'!'|if|then|else|elif|do|while|until|fi|done|eval) shift;;
        *=*) case "$1" in -*) break;; esac; shift;;
        env) shift; while [ $# -gt 0 ]; do case "$1" in -u|-S|-C|--unset|--chdir) shift 2;; -*|*=*) shift;; *) break;; esac; done;;
        sudo|doas) shift; while [ $# -gt 0 ]; do case "$1" in -u|-g|-C|-h|-p|-r|-t|-U|-D) shift 2;; -*) shift;; *) break;; esac; done;;
        nohup|exec|command|builtin|time|caffeinate|stdbuf|unbuffer|chronic|parallel|busybox) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done;;
        nice) shift; [ "${1:-}" = -n ] && shift 2; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done;;
        timeout) shift; while [ $# -gt 0 ]; do case "$1" in -s|-k|--signal|--kill-after) shift 2;; -*) shift;; *) break;; esac; done; shift;;
        xargs) shift; while [ $# -gt 0 ]; do case "$1" in -I|-n|-L|-P|-s|-E|-d) shift 2;; -*) shift;; *) break;; esac; done;;
        watch) shift; while [ $# -gt 0 ]; do case "$1" in -n|-d|--interval) shift 2;; -*) shift;; *) break;; esac; done;;
        flock) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done; shift;;
        script) shift; while [ $# -gt 0 ]; do case "$1" in -c) shift; break;; -*) shift;; *) shift; break;; esac; done;;
        ssh) shift; while [ $# -gt 0 ]; do case "$1" in -[bcDEeFIiJLlmOopQRSWw]) shift 2;; -*) shift;; *) shift; break;; esac; done;;
        bash|sh|zsh|dash|ksh|source|.) shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done;;
        echo|printf) if [ "$PIPED" = 1 ]; then shift; while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done; else break; fi;;
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
PROGS=$(printf '%s\n' "$CMDS" | awk 'NF{print $1}')
runs() { printf '%s\n' "$PROGS" | grep -Eq "^($1)$"; }
in_coord() { [ -n "$COORD_DIR" ] && [ "$CWD" = "$COORD_DIR" ]; }

# A variable as the command name can be anything (`p=pkill; $p -f x`): refuse rather than guess.
printf '%s\n' "$PROGS" | grep -q '\$' && out deny "A variable can't be used as the command name here (lane-guard). Write the command out."
# A command name starting with "-" means something substituted the real name in front (`\`echo pkill\` -f x`).
printf '%s\n' "$PROGS" | grep -q '^-' && out deny "A substituted command name can't be checked (lane-guard). Write the command out."
# A `cd` earlier in the same command moves where git runs, so the branch the guard reads may be the wrong one.
CD_SEEN=0; runs 'cd|pushd' && CD_SEEN=1

# --- merges: coordinator only ------------------------------------------------------------------------------------
if runs "($COORD_SCRIPTS)\.sh"; then
  in_coord || out deny "Merge/release scripts are coordinator-only (lane-guard). Report 'ready at <full sha>' to the coordinator."
fi
is_merge() {
  local g; g=$(printf '%s\n' "$CMDS" | awk '$1=="gh"' | grep -Ev '[[:space:]](--help|-h)([[:space:]]|$)')
  printf '%s\n' "$g" | grep -Eq '(^|[[:space:]])pr([[:space:]].*)?[[:space:]]merge([[:space:]]|$)' && return 0
  printf '%s\n' "$CMDS" | grep -E '^(gh|curl|wget|http|https) ' \
    | grep -Eq '/pulls/[0-9]+/merge([[:space:]?/]|$)|/merges([[:space:]?]|$)|mergePullRequest|enablePullRequestAutoMerge|mergeBranch' && return 0
  # Moving a branch through the API (PATCH/POST/DELETE git/refs, updateRef) is a push without git: coordinator-only.
  printf '%s\n' "$CMDS" | grep -E '^(gh|curl|wget|http|https) ' | grep -E '/git/refs|updateRef|createRef|deleteRef' \
    | grep -Eq '(-X|--method|--request)[[:space:]=]*(PATCH|POST|PUT|DELETE)|[[:space:]](-f|-F|--field|--raw-field|--input|-d|--data[a-z-]*)([[:space:]=]|$)|mutation'
}
if is_merge; then
  in_coord || out deny "Lanes never merge (lane-guard). Report 'ready at <full sha>' to the coordinator."
fi

# --- the controls themselves: owner-only ---------------------------------------------------------------------------
runs 'human-approve\.sh|human-a[^ ]*[*?[][^ ]*' && out deny "Only a person records a human review, with a '!' line in the pane (lane-guard)."
runs 'tests-lock\.sh|tests-l[^ ]*[*?[][^ ]*'   && out deny "Only the owner locks or unlocks tests, with a '!' line in the pane (lane-guard)."
# File-changing programs (sed/perl only with -i; python/node/ruby when the command text names a protected path).
MUTATORS='rm|rmdir|unlink|shred|mv|cp|ln|tee|truncate|touch|chmod|chown|dd|install|rsync|ed|vi|vim|nano|emacs|tar|bsdtar|unzip|ditto|patch'
PROTECTED='merge-queue/|human-approved|tests-lock|\.claude/(hooks|lib|kit|agents|roles|skills|guard\.conf|trusted-repos|settings[^ ]*\.json|CLAUDE\.md|lanes\.zsh|gos|kit-tools)|\.claude/[*?[]|(^|[[:space:]/~])\.claude/?([[:space:]]|$)'
# The other agent CLIs' hook configs and rules (install.sh --tool): changing them would switch their guards off.
PROTECTED="$PROTECTED"'|\.codex/(hooks\.json|config\.toml|AGENTS\.md)|\.config/opencode/(plugins?|opencode\.jsonc?|AGENTS\.md)|\.gemini/(config/hooks\.json|antigravity-cli/settings\.json|AGENTS\.md)'
# ...and those folders as a whole (rm -rf ~/.codex, mv ~/.gemini x), or through a wildcard anywhere below them
# (rm ~/.codex/hook*, rm ~/.claude/hook*/lane-guard.sh): a glob can expand to a protected file.
PROTECTED="$PROTECTED"'|(^|[[:space:]/~])(\.codex|\.gemini(/config|/antigravity-cli)?|\.config/opencode(/plugins?)?)/?([[:space:]]|$)|(\.claude|\.codex|\.gemini|\.config/opencode)/[^[:space:]]*[*?[]'
# Right under your home: ~/.config itself (it holds opencode/), and a wildcard in a dot-folder's name (~/.c*,
# ~/.cod*, ~/.conf*/opencode). A project's own .config folder is not affected.
HOMEP='(~|\$\{?HOME\}?|/Users/[^/[:space:]]+|/home/[^/[:space:]]+)'
PROTECTED="$PROTECTED|$HOMEP"'/(\.config/?([[:space:]]|$)|\.config/[^/[:space:]]*[*?[]|\.[^/[:space:]]*[*?[])'
# A `..` after one of these folders can lead back into anything (~/.config/opencode/../opencode).
PROTECTED="$PROTECTED"'|(\.claude|\.codex|\.gemini|\.config)(/[^[:space:]]*)?/\.\.(/|[[:space:]]|$)'
# Matched without regard to case: the default macOS disk ignores it, so ~/.CODEX/hooks.json is the same file.
touches_protected() {
  # Doubled slashes and /./ name the same place (rm -rf ~/.codex//), so they're squeezed out before matching.
  squeeze() { perl -pe 's#/+#/#g; 1 while s#/\./#/#g; s#/\.(?=\s|$)##g'; }
  local CMDS SRC; CMDS=$(printf '%s\n' "$CMDS_RAW" | squeeze); SRC=$(printf '%s' "$SRC_RAW" | squeeze)
  local FINDMUT='^find .*[[:space:]](-delete|-exec|-execdir|-ok|-okdir|-fprint|-fprintf|-fls)([[:space:]]|$)'
  printf '%s\n' "$CMDS" | grep -E "$FINDMUT" | grep -Eiq -- "$PROTECTED" && return 0
  printf '%s\n' "$CMDS" | grep -E "^($MUTATORS)( |$)|^(sed|perl|gsed) .*(-i|--in-place)|^git( .*)? (rm|mv|clean|checkout|restore)( |$)|^(curl|wget)( .*)?[[:space:]](-[a-zA-Z]*[oO]|--output|--output-document)([[:space:]=]|$)" \
    | grep -Eiq -- "$PROTECTED" && return 0
  # `cd ~/.claude` (or anywhere inside it) then a relative path: any file change in that command counts.
  if printf '%s\n' "$CMDS" | grep -E '^(cd|pushd) ' | grep -Eiq '\.(claude|codex|gemini)([/[:space:]]|$)|\.config(/opencode)?/?([[:space:]]|$)|\.config/opencode/|merge-queue'; then
    printf '%s\n' "$CMDS" | grep -Eq "^($MUTATORS)( |$)|$FINDMUT|^(sed|perl|gsed) .*(-i|--in-place)|^(curl|wget) " && return 0
    printf '%s' "$SRC" | grep -q '>' && return 0
  fi
  runs 'python|python3|node|ruby|perl' && printf '%s' "$SRC" | grep -Eiq -- "$PROTECTED" && return 0
  printf '%s' "$SRC" | grep -Eiq -- ">[[:space:]]*[^[:space:]]*($PROTECTED)"
}
CMDS_RAW=$CMDS SRC_RAW=$SRC touches_protected && out deny "That would change the guard's own controls (hooks, settings, trust list, approvals or the test lock). Owner-only (lane-guard)."

if [ "${GOS_PROTECT:-0}" = 1 ]; then   # optional: a "go" (the owner's approval file) only comes from the owner
  runs 'go\.sh' && out deny "Only the owner records a go, with a '!' line in the pane (lane-guard)."
fi

# --- pattern kills ---------------------------------------------------------------------------------------------------
KILLMSG="Killing by pattern can stop other sessions' jobs (lane-guard). Stop your own process by its PID, or use stop_own from ~/.claude/lib/opslib.sh."
runs 'pkill|killall' && out deny "$KILLMSG"
runs pgrep && runs kill && out deny "$KILLMSG"   # kill $(pgrep -f …) / pgrep -f … | xargs kill

# --- git: push rules ---------------------------------------------------------------------------------------------------
push_verdict() {
  printf '%s\n' "$CMDS" | awk '$1=="git"' | while read -r _ rest; do
    set -f
    # shellcheck disable=SC2086
    set -- $rest
    D=$CWD
    while [ $# -gt 0 ]; do   # global options before the subcommand
      case "$1" in
        -C) D=$2; shift 2;;
        -c) case "${2:-}" in alias.*|remote.*|push.*|branch.*) echo "CONFIG";; esac; shift 2;;
        -calias.*|-cremote.*|-cpush.*|-cbranch.*) echo "CONFIG"; shift;;
        --git-dir=*|--work-tree=*|--namespace=*|-c*|--no-pager|-p|--paginate|--bare|--no-replace-objects) shift;;
        --git-dir|--work-tree|--namespace) shift 2;; *) break;;
      esac
    done
    case "${1:-}" in
      config) printf '%s ' "$@" | grep -Eq '(^| )(remote\.[^ ]*\.push|push\.[^ ]*|branch\.[^ ]*\.merge|alias\.[^ ]*)( |=|$)' && echo "CONFIG"; continue;;
      push) shift;;
      subtree) [ "${2:-}" = push ] || continue; shift 2   # git subtree push --prefix=P REMOTE BRANCH
        # shellcheck disable=SC2046
        set -- $(printf '%s\n' "$@" | grep -v -- '^--prefix'); [ "${1:-}" = -P ] && shift 2;;
      *) continue;;
    esac
    CUR=$(git -C "$D" symbolic-ref --short -q HEAD 2>/dev/null)
    npos=0; skip=0
    for a in "$@"; do
      [ "$skip" = 1 ] && { skip=0; continue; }
      case "$a" in
        -o|--push-option|--repo|--receive-pack|--exec) skip=1;;
        --force-with-lease*|--force-if-includes) ;;
        --force|--force=*) echo "FORCE";;
        --all|--mirror|--branches) echo "MAIN";;
        --*) ;;
        -*f*) echo "FORCE";;                     # -f, -uf, -fu…: any short-flag cluster with f
        +*) echo "FORCE";;                       # +refspec
        -*) ;;
        *) npos=$((npos + 1))
           [ "$npos" -ge 2 ] || continue        # the first positional is the remote
           case "$a" in *'$'*|*'`'*) echo "UNKNOWN"; continue;; esac
           case "$a" in *'*'*|:) echo "MAIN"; continue;; esac   # glob or "matching" refspec: can include main
           dst=${a#*:}; dst=${dst#refs/}; dst=${dst#heads/}
           case "$dst" in HEAD|@|'') [ "$CD_SEEN" = 1 ] && { echo "CDPUSH"; continue; }; dst=$CUR;; esac
           case "$dst" in main|master) echo "MAIN";; esac;;
      esac
    done
    if [ "$npos" -lt 2 ]; then
      [ "$CD_SEEN" = 1 ] && echo "CDPUSH"
      case "$CUR" in main|master) echo "BAREMAIN";; esac
    fi
    set +f
  done
}
PUSH=$(push_verdict)
case "$PUSH" in
  *CONFIG*) out deny "Push, branch or alias settings via git -c / git config are blocked: they can redirect a push (lane-guard).";;
  *FORCE*) out deny "Force push is blocked (lane-guard). Use --force-with-lease on your own feature branch only.";;
  *UNKNOWN*) out deny "A push refspec built from a variable can't be checked (lane-guard). Write the branch name out.";;
  *CDPUSH*) out deny "After a cd, the guard can't tell which branch a bare or HEAD push would update (lane-guard). Push with the branch name written out, e.g. git push origin my-branch.";;
  *BAREMAIN*) out deny "You are on main/master; a bare push would update it (lane-guard). Create a feature branch first.";;
  *MAIN*) out deny "Pushing to main/master is blocked (lane-guard). Push a feature branch and report 'ready at <sha>' to the coordinator.";;
esac

# --- prod AWS: ask for anything but read-only verbs --------------------------------------------------------------------
if [ -n "$PROD_PROFILE" ] && runs aws; then
  prod_env=0
  printf '%s' "$SRC" | grep -Eq "AWS_(DEFAULT_)?PROFILE=$PROD_PROFILE([[:space:];&|]|\$)" && prod_env=1
  printf '%s\n' "$CMDS" | awk '$1=="aws"' | while read -r _ rest; do
    set -f
    # shellcheck disable=SC2086
    set -- $rest
    prof=$prod_env; svc=""; verb=""; args=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --profile) [ "${2:-}" = "$PROD_PROFILE" ] && prof=1; shift 2;;
        --profile=*) [ "${1#--profile=}" = "$PROD_PROFILE" ] && prof=1; shift;;
        --region|--output|--endpoint-url|--query|--cli-read-timeout|--cli-connect-timeout|--color|--ca-bundle) shift 2;;
        -*) shift;;
        *) if [ -z "$svc" ]; then svc=$1; elif [ -z "$verb" ]; then verb=$1; else args="$args $1"; fi; shift;;
      esac
    done
    [ "$prof" = 1 ] || continue
    if [ "$svc" = s3 ]; then
      case "$verb" in ls|presign) ;; cp) case "$args" in *' s3://'*) last=${args##* }; case "$last" in s3://*) echo ASK;; esac;; esac;;
        *) echo ASK;; esac
    else
      case "$verb" in get-*|list-*|describe-*|head-*|lookup-*|filter-*|wait|help|search-*|query|scan|batch-get-*|simulate-*|ls|'') ;;
        *) echo ASK;; esac
    fi
    set +f
  done | grep -q ASK && out ask "Prod AWS write (lane-guard). Approve only if the owner's go for exactly this is in this pane."
fi
exit 0
