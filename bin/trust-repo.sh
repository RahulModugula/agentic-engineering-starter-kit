#!/bin/bash
# trust-repo.sh [REPO_DIR] | --list | --remove REPO_DIR
# Let the Stop hook run this repo's own check command (.claude/check, `make check` or `npm test`) when a session ends.
# Only trust repos whose code you trust: the check runs on your machine as you.
set -euo pipefail
F=${TRUSTED_REPOS_FILE:-$HOME/.claude/trusted-repos}
mkdir -p "$(dirname "$F")"; touch "$F"
case "${1:-}" in
  --list) cat "$F";;
  --remove) r=$(cd "${2:?usage: trust-repo.sh --remove REPO_DIR}" && git rev-parse --show-toplevel)
            grep -vxF "$r" "$F" > "$F.tmp" || true; mv "$F.tmp" "$F"; echo "untrusted: $r";;
  *) r=$(cd "${1:-.}" && git rev-parse --show-toplevel)
     grep -qxF "$r" "$F" || echo "$r" >> "$F"; echo "trusted: $r";;
esac
