#!/bin/bash
# go.sh: record the OWNER's go for one exact run of an ops script (change 4, off by default).
# Run it yourself with a leading `!` in any Claude pane (a `!` line is your input, not a tool call):
#   ! ~/agentic-starter-kit/bin/go.sh path/to/script.sh [--ttl-hours 12] [--env "VAR1 VAR2"] [--files "a.py b.py"] -- [script args]
# It prints what the go covers and writes $GO_DIR/<fingerprint>.go. The script calls `require_go` (opslib.sh) and
# runs only if a go exists for the SAME script bytes, args, listed env values and listed source files.
# A go is consumed by require_go (one run) unless the script sets GO_REUSE=1.
set -euo pipefail
# shellcheck source=/dev/null
. "${OPSLIB:-$HOME/.claude/lib/opslib.sh}"
[ $# -ge 1 ] || { sed -n '2,8p' "$0"; exit 2; }
script=$1; shift; ttl=12; envs=""; files=""
while [ $# -gt 0 ]; do
  case "$1" in --ttl-hours) ttl=$2; shift 2;; --env) envs=$2; shift 2;; --files) files=$2; shift 2;; --) shift; break;; *) break;; esac
done
[ -f "$script" ] || { echo "go: no such script: $script" >&2; exit 2; }
fp=$(GO_ENV="$envs" GO_FILES="$files" go_fingerprint "$script" "$@")
dir=${GO_DIR:-$HOME/.claude/gos}; mkdir -p "$dir"; chmod 700 "$dir"
exp=$(( $(date +%s) + ttl * 3600 ))
{
  echo "script=$(cd "$(dirname "$script")" && pwd)/$(basename "$script")"
  echo "script_sha256=$(shasum -a 256 "$script" | cut -d' ' -f1)"
  echo "args=$*"
  for v in $envs; do echo "env.$v=${!v-<unset>}"; done
  for f in $files; do echo "file.$f=$(shasum -a 256 "$f" | cut -d' ' -f1)"; done
  echo "expires_epoch=$exp"
  echo "granted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$dir/$fp.go"
chmod 600 "$dir/$fp.go"
echo "GO recorded for one run, expires in ${ttl}h:"; sed 's/^/  /' "$dir/$fp.go"
