#!/bin/bash
# scan.sh [--history] [--names FILE] [DIR]: refuse to share a repo that holds secrets, personal data or session state.
#   (default)   scan the files git would commit (tracked + untracked, not ignored) in DIR (default: this repo)
#   --history   ALSO scan every blob in every commit of DIR's git history
#   --names F   ALSO flag any line matching a pattern in F (one ERE per line): e.g. company/project/people names
# Uses gitleaks for secrets when installed (`brew install gitleaks`); the built-in rules always run too.
# Prints rule, file and line number only, never the matched text. Exit 0 = clean, 1 = findings, 2 = error.
set -uo pipefail
hist=0; names=""; dir=""
while [ $# -gt 0 ]; do case "$1" in --history) hist=1; shift;; --names) names=$2; shift 2;; *) dir=$1; shift;; esac; done
dir=${dir:-$(cd "$(dirname "$0")/.." && pwd)}
if [ -n "$names" ]; then   # resolve before cd, and refuse rather than "pass" if it can't be read
  case "$names" in /*) ;; *) names="$PWD/$names";; esac
  { [ -f "$names" ] && [ -r "$names" ] && [ -s "$names" ]; } || { echo "scan: names file missing, unreadable or empty: $names" >&2; exit 2; }
  grep -Eif "$names" /dev/null >/dev/null 2>&1; [ $? -eq 2 ] && { echo "scan: a pattern in $names is invalid" >&2; exit 2; }
fi
cd "$dir" || exit 2
git rev-parse --git-dir >/dev/null 2>&1 || { echo "scan: $dir is not a git repo" >&2; exit 2; }

# name|ERE. Secrets first, then personal data, then session state by path.
RULES='aws-access-key|(AKIA|ASIA)[0-9A-Z]{16}
private-key|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----
github-token|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}
anthropic-key|sk-ant-[A-Za-z0-9_-]{20,}
openai-key|sk-(proj-)?[A-Za-z0-9]{32,}
slack-token|xox[abprs]-[A-Za-z0-9-]{10,}
plane-token|plane_api_[A-Za-z0-9]{20,}
generic-secret|(api[_-]?key|secret|token|passw(or)?d)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9/+_=-]{20,}["'"'"']
email|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# Emails that are fine to ship: placeholders and tool attributions.
EMAIL_OK='@(example\.(com|org|test)|users\.noreply\.github\.com|anthropic\.com)$|(^|:)(you|user|name|me)@'
BAD_PATHS='(^|/)(projects|memory|todos|shell-snapshots|statsig|ide|sessions)/|(^|/)hooks/\.state/|\.jsonl$|(^|/)\.credentials\.json$|(^|/)\.secrets/|(^|/)\.env(\.|$)|(^|/)skills/synced/|scratchpad/'

found=0
report() { echo "FINDING $1: $2${3:+:$3}"; found=1; }

scan_text() {  # scan_text LABEL < content. One grep per rule over the whole text (fast enough for a pre-commit hook).
  local label=$1 name re ln t
  t=$(mktemp); cat > "$t"
  while IFS='|' read -r name re; do
    [ -z "$name" ] && continue
    if [ "$name" = email ]; then
      # Line number + each address; drop allowed placeholders; report the first bad address per line.
      for ln in $(LC_ALL=C grep -nEo -- "$re" "$t" | grep -Ev -- "$EMAIL_OK" | cut -d: -f1 | uniq); do report email "$label" "$ln"; done
    else
      for ln in $(LC_ALL=C grep -nE -- "$re" "$t" | cut -d: -f1); do report "$name" "$label" "$ln"; done
    fi
  done <<<"$RULES"
  if [ -n "$names" ]; then
    for ln in $(LC_ALL=C grep -niE -f "$names" "$t" | cut -d: -f1); do report name "$label" "$ln"; done
  fi
  rm -f "$t"
}

# Working tree: what a commit would include.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  printf '%s' "$f" | grep -Eq "$BAD_PATHS" && report session-state-path "$f"
  [ -n "$names" ] && printf '%s' "$f" | grep -Eiq -f "$names" && report name-in-path "$f"
  file -b --mime "$f" | grep -q 'charset=binary' && continue
  scan_text "$f" < "$f"
done < <(git ls-files --cached --others --exclude-standard)

if [ $hist = 1 ]; then
  while read -r obj path; do
    [ -n "$path" ] || continue
    printf '%s' "$path" | grep -Eq "$BAD_PATHS" && report session-state-path-in-history "$path"
    [ -n "$names" ] && printf '%s' "$path" | grep -Eiq -f "$names" && report name-in-history-path "$path"
    git cat-file -p "$obj" 2>/dev/null | LC_ALL=C grep -Iq . || continue
    scan_text "history:$path@${obj:0:8}" < <(git cat-file -p "$obj")   # not a pipe: found=1 must survive
  done < <(git rev-list --all --objects | awk 'NF==2' | sort -u -k1,1)
fi

if command -v gitleaks >/dev/null 2>&1; then
  if [ $hist = 1 ]; then gitleaks detect --source . --redact --no-banner -q || found=1
  else gitleaks detect --source . --no-git --redact --no-banner -q || found=1; fi
fi

[ $found = 0 ] && echo "SCAN CLEAN: $dir${hist:+ }$([ $hist = 1 ] && echo '(working tree + full history)' || echo '(working tree)')"
exit $found
