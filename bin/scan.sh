#!/bin/bash
# scan.sh [--history] [--names FILE] [DIR]: refuse to share a repo that holds secrets, personal data or session state.
#   (default)   scan the files git would commit (tracked + untracked, not ignored) in DIR (default: this repo)
#   --history   ALSO scan every blob in every commit of DIR's git history, every author/committer email,
#               and every commit message
#   --names F   ALSO flag any line matching a pattern in F (one ERE per line): e.g. company/project/people names
# Uses gitleaks for secrets when installed (`brew install gitleaks`); the built-in rules always run too.
# Prints rule, file and line number only, never the matched text. Exit 0 = clean, 1 = findings, 2 = error.
set -uo pipefail
usage() { echo "usage: scan.sh [--history] [--names FILE] [DIR]" >&2; exit 2; }
hist=0; names=""; dir=""
while [ $# -gt 0 ]; do case "$1" in
  --history) hist=1; shift;;
  --names) { [ $# -ge 2 ] && [ -n "$2" ]; } || usage; names=$2; shift 2;;
  *) dir=$1; shift;;
esac; done
dir=${dir:-$(cd "$(dirname "$0")/.." && pwd)}
if [ -n "$names" ]; then   # resolve before cd, and refuse rather than "pass" if it can't be read
  case "$names" in /*) ;; *) names="$PWD/$names";; esac
  { [ -f "$names" ] && [ -r "$names" ] && [ -s "$names" ]; } || { echo "scan: names file missing, unreadable or empty: $names" >&2; exit 2; }
  grep -Eif "$names" /dev/null >/dev/null 2>&1; [ $? -eq 2 ] && { echo "scan: a pattern in $names is invalid" >&2; exit 2; }
fi
cd "$dir" || exit 2
git rev-parse --git-dir >/dev/null 2>&1 || { echo "scan: $dir is not a git repo" >&2; exit 2; }

# name|ERE, one per line. The name ends at the FIRST '|'; the rest of the line (which may hold '|') is the ERE.
# Secrets first, then personal data. A quoted heredoc, so the patterns need no shell escaping.
# A one-character class like [ ] or [T] is deliberate: it stops a rule matching its own line when this file is scanned.
read -r -d '' RULES <<'EOF'
aws-access-key|(AKIA|ASIA)[0-9A-Z]{16}
aws-secret|(aws_secret_access_key|AWS_SECRET_ACCESS_KEY)[[:space:]]*[:=][[:space:]]*["']?[A-Za-z0-9/+=]{40}
private-key|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----
key-other|BEGIN PGP PRIVATE KEY[ ]BLOCK|PuTTY-User-Key-File-[0-9]
github-token|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}
gitlab|glpat-[A-Za-z0-9_-]{20}
anthropic-key|sk-ant-[A-Za-z0-9_-]{20,}
openai-key|sk-(proj-)?[A-Za-z0-9]{32,}
gcp-api-key|AIza[0-9A-Za-z_-]{35}
gcp-oauth|GOCSPX-[A-Za-z0-9_-]{24,}
azure-key|AccountKey=[A-Za-z0-9+/]{86}==
azure-sas|[?&]sig=[A-Za-z0-9%]{30,}
jwt|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
stripe|(sk|rk)_live_[A-Za-z0-9]{20,}
npm-token|_auth[T]oken=[^[:space:]]+|npm_[A-Za-z0-9]{36}
pypi|pypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{20,}
sendgrid|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{30,}
slack-token|xox[abprs]-[A-Za-z0-9-]{10,}
slack-hook|hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+
plane-token|plane_api_[A-Za-z0-9]{20,}
url-creds|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]{3,}@
generic-secret|(api[_-]?key|secret|token|passw(or)?d)["']?[[:space:]]*[:=][[:space:]]*["'][A-Za-z0-9/+_=-]{20,}["']
generic-unquoted|(api[_-]?key|secret|token|passw(or)?d)[A-Za-z_]*[[:space:]]*[:=][[:space:]]*["']?[A-Za-z0-9/+_=-]{20,}
email|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}
EOF
# Emails that are fine to ship: placeholders and tool attributions.
EMAIL_OK='@(example\.(com|org|test)|users\.noreply\.github\.com|anthropic\.com)$|(^|:)(you|user|name|me)@'
EMAIL_RE=$(printf '%s\n' "$RULES" | sed -n 's/^email|//p')
BAD_PATHS='(^|/)(projects|memory|todos|shell-snapshots|statsig|ide|sessions)/|(^|/)hooks/\.state/|\.jsonl$|(^|/)\.credentials\.json$|(^|/)\.secrets/|(^|/)\.env(\.|$)|(^|/)skills/synced/|scratchpad/'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/scan.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
# Every non-email rule in one pattern file: one grep per text decides whether the per-rule greps are needed.
printf '%s\n' "$RULES" | sed -e '/^email|/d' -e 's/^[^|]*|//' > "$WORK/secrets.ere"

found=0
report() { echo "FINDING $1: $2${3:+:$3}"; found=1; }

rule_hits() {  # rule_hits FILE: print "rule line" per finding. One grep per rule over the whole file, never per line.
  local f=$1 name re ln any
  LC_ALL=C grep -qE -f "$WORK/secrets.ere" -- "$f" 2>/dev/null; any=$?   # 1 = no secret rule can match
  while IFS='|' read -r name re; do
    [ -z "$name" ] && continue
    if [ "$name" = email ]; then
      # Line number + each address; drop allowed placeholders; report the first bad address per line.
      for ln in $(LC_ALL=C grep -nEo -- "$re" "$f" | grep -Ev -- "$EMAIL_OK" | cut -d: -f1 | uniq); do echo "email $ln"; done
    elif [ $any -ne 1 ]; then
      for ln in $(LC_ALL=C grep -nE -- "$re" "$f" | cut -d: -f1); do echo "$name $ln"; done
    fi
  done <<<"$RULES"
  if [ -n "$names" ]; then
    for ln in $(LC_ALL=C grep -niE -f "$names" -- "$f" | cut -d: -f1); do echo "name $ln"; done
  fi
}

scan_file() {  # scan_file LABEL FILE
  local name ln
  while read -r name ln; do report "$name" "$1" "$ln"; done < <(rule_hits "$2")   # not a pipe: found=1 must survive
}

# Working tree: what a commit would include. NUL-separated, so spaces and non-ASCII names arrive intact.
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  printf '%s' "$f" | grep -Eq "$BAD_PATHS" && report session-state-path "$f"
  [ -n "$names" ] && printf '%s' "$f" | grep -Eiq -f "$names" && report name-in-path "$f"
  file -b --mime "./$f" | grep -q 'charset=binary' && continue
  scan_file "$f" "./$f"
done < <(git ls-files -z --cached --others --exclude-standard)

if [ $hist = 1 ]; then
  # Every blob reachable from any ref, once. %(rest) keeps a path with spaces whole.
  while IFS= read -r line; do
    obj=${line%% *}; path=${line#* }
    [ -n "$path" ] && [ "$path" != "$line" ] || continue
    printf '%s' "$path" | grep -Eq "$BAD_PATHS" && report session-state-path-in-history "$path"
    [ -n "$names" ] && printf '%s' "$path" | grep -Eiq -f "$names" && report name-in-history-path "$path"
    git cat-file blob "$obj" > "$WORK/blob" 2>/dev/null || continue
    LC_ALL=C grep -Iq . "$WORK/blob" || continue
    scan_file "history:$path@${obj:0:8}" "$WORK/blob"
  done < <(git rev-list --all --objects | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' |
           sed -n 's/^blob //p' | sort -u -k1,1)

  # Commit metadata: author and committer emails, checked against the same allow-list as file content.
  git log --all --format='%H:%ae%n%H:%ce' > "$WORK/emails" 2>/dev/null
  for c in $(LC_ALL=C grep -E -- "${EMAIL_RE}\$" "$WORK/emails" | grep -Ev -- "$EMAIL_OK" | cut -d: -f1 | uniq); do
    report commit-email "history:commit@${c:0:8}"
  done
  # Commit messages: every rule, mapped back to the commit. msgs line N belongs to the commit on owners line N.
  sep=$(printf '\001')
  git log --all --format="${sep}%H%n%B" 2>/dev/null |
    awk -v sep="$sep" -v o="$WORK/owners" 'substr($0,1,1)==sep { c=substr($0,2); next } { print; print c > o }' > "$WORK/msgs"
  if [ -s "$WORK/msgs" ]; then
    while read -r name c; do report "$name" "history:commit-message@${c:0:8}"; done < <(
      rule_hits "$WORK/msgs" | awk 'NR==FNR { o[NR]=$0; next } { print $1, o[$2] }' "$WORK/owners" - | sort -u)
  fi
fi

if command -v gitleaks >/dev/null 2>&1; then
  if [ $hist = 1 ]; then gitleaks detect --source . --redact --no-banner -q || found=1
  else gitleaks detect --source . --no-git --redact --no-banner -q || found=1; fi
fi

[ $found = 0 ] && echo "SCAN CLEAN: $dir${hist:+ }$([ $hist = 1 ] && echo '(working tree + full history)' || echo '(working tree)')"
exit $found
