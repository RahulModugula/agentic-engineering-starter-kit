# opslib.sh: helpers for long-running ops scripts. Source it: `. ~/.claude/lib/opslib.sh`
#
# Why each helper exists (failures it replaces):
#   wait_marker / wait_log  - a `pgrep -f <name>` watcher kept matching a process whose command line held the same
#                             pattern (macOS pgrep skips itself and its ancestors, so a sibling), and never fired
#                             (~35 min lost). Watch for the job's OUTPUT instead.
#   launch / alive          - a shared `pkill -f` pattern killed 5 unrelated jobs; track YOUR process by pidfile.
#   need_creds              - SSO expired mid-run at least 4 times; check the token's remaining life before starting.
#   is_auth_error           - a per-item catch recorded expired credentials as data errors; stop instead (exit 3).
#   retry                   - one transient read during a laptop network drop STOPped a feed after all its sends.
#
# Exit/return codes: 0 ok, 1 condition false, 2 usage error, 3 credentials, 124 timeout (like timeout(1)).
# Bash 3.2 compatible (macOS /bin/bash). No pgrep/pkill anywhere.

OPS_POLL="${OPS_POLL:-5}"   # seconds between checks; tests set it low

_ops_now() { date +%s; }

# wait_marker FILE TIMEOUT_SECONDS -> 0 when FILE exists, 124 on timeout.
wait_marker() {
  [ $# -eq 2 ] || { echo "usage: wait_marker FILE TIMEOUT" >&2; return 2; }
  local f=$1 end=$(( $(_ops_now) + $2 ))
  while :; do
    [ -e "$f" ] && return 0
    [ "$(_ops_now)" -ge "$end" ] && { echo "wait_marker: timeout after $2s waiting for $f" >&2; return 124; }
    sleep "$OPS_POLL"
  done
}

# wait_log FILE ERE TIMEOUT_SECONDS -> 0 when a line matching ERE appears in FILE, 124 on timeout.
# Only lines appended after the call count when OPS_FROM_END=1 (default 0: whole file).
wait_log() {
  [ $# -eq 3 ] || { echo "usage: wait_log FILE REGEX TIMEOUT" >&2; return 2; }
  local f=$1 re=$2 end=$(( $(_ops_now) + $3 )) skip=0
  [ "${OPS_FROM_END:-0}" = 1 ] && [ -f "$f" ] && skip=$(wc -l < "$f" | tr -d ' ')
  while :; do
    [ -f "$f" ] && tail -n "+$((skip + 1))" "$f" | grep -Eq -- "$re" && return 0
    [ "$(_ops_now)" -ge "$end" ] && { echo "wait_log: timeout after $3s waiting for /$re/ in $f" >&2; return 124; }
    sleep "$OPS_POLL"
  done
}

# _ops_start_time PID -> the process start time as ps prints it (guards against PID reuse).
_ops_start_time() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }

# launch PIDFILE CMD [ARGS...] -> runs CMD in the background (nohup), writes "PID<TAB>start-time" to PIDFILE.
launch() {
  [ $# -ge 2 ] || { echo "usage: launch PIDFILE CMD [ARGS...]" >&2; return 2; }
  local pf=$1; shift
  nohup "$@" >/dev/null 2>&1 &
  local pid=$!
  printf '%s\t%s\n' "$pid" "$(_ops_start_time "$pid")" > "$pf"
  echo "$pid"
}

# alive PIDFILE -> 0 if the process recorded in PIDFILE is still the same process, 1 otherwise.
alive() {
  [ $# -eq 1 ] || { echo "usage: alive PIDFILE" >&2; return 2; }
  [ -f "$1" ] || return 1
  local pid st
  IFS=$'\t' read -r pid st < "$1"
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  # A recycled PID has a different start time. No recorded (or readable) start time means we can't tell the
  # process from a stranger that reused its PID, so it doesn't count as alive.
  [ -n "$st" ] || return 1
  local now; now=$(_ops_start_time "$pid")
  [ -n "$now" ] && [ "$now" = "$st" ]
}

# stop_own PIDFILE -> TERM only the process recorded in PIDFILE (never a pattern).
stop_own() {
  alive "$1" || return 1
  local pid; IFS=$'\t' read -r pid _ < "$1"
  kill "$pid"
}

# sso_minutes_left PROFILE -> prints whole minutes until the profile's SSO token expires; 3 if none/expired.
# Reads only expiresAt/startUrl from ~/.aws/sso/cache; never prints a token.
sso_minutes_left() {
  [ $# -eq 1 ] || { echo "usage: sso_minutes_left PROFILE" >&2; return 2; }
  /usr/bin/python3 - "$1" "${AWS_CONFIG_FILE:-$HOME/.aws/config}" "${OPS_SSO_CACHE:-$HOME/.aws/sso/cache}" <<'PY'
import configparser, datetime as dt, glob, json, os, sys
profile, cfg_path, cache = sys.argv[1:4]
cfg = configparser.RawConfigParser(); cfg.read(cfg_path)
sec = "default" if profile == "default" else f"profile {profile}"
if not cfg.has_section(sec):
    print(f"need_creds: no profile {profile!r} in {cfg_path}", file=sys.stderr); sys.exit(3)
p = dict(cfg.items(sec))
session = p.get("sso_session")
start = cfg.get(f"sso-session {session}", "sso_start_url", fallback=None) if session else p.get("sso_start_url")
if not start:
    print(f"need_creds: profile {profile!r} is not an SSO profile", file=sys.stderr); sys.exit(3)
import hashlib
best, refreshable = None, False
for f in glob.glob(os.path.join(cache, "*.json")):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if d.get("startUrl") == start and d.get("expiresAt") and "accessToken" in d:
        exp = dt.datetime.fromisoformat(d["expiresAt"].replace("Z", "+00:00"))
        best = exp if best is None or exp > best else best
        refreshable = refreshable or bool(d.get("refreshToken"))
if best is None:
    print(f"need_creds: no cached SSO token for {profile!r}; run: aws sso login --profile {profile}", file=sys.stderr); sys.exit(3)
if refreshable:
    # sso-session: expiresAt is the hourly access token, refreshed automatically. The real limit is the Identity
    # Center session, counted from sign-in, which the cache doesn't record; bin/sso-login.sh records it.
    rec = os.path.join(os.environ.get("OPS_SSO_LOGIN_DIR", os.path.expanduser("~/.aws/sso/login-times")),
                       hashlib.sha1(start.encode()).hexdigest())
    try:
        login = dt.datetime.fromtimestamp(int(open(rec).read().strip()), dt.timezone.utc)
    except Exception:
        print(f"need_creds: refreshable SSO session but no sign-in record; sign in with bin/sso-login.sh {profile}", file=sys.stderr); sys.exit(3)
    best = login + dt.timedelta(hours=float(os.environ.get("OPS_SSO_SESSION_HOURS", "8")))
mins = int((best - dt.datetime.now(dt.timezone.utc)).total_seconds() // 60)
print(max(mins, 0))
sys.exit(0 if mins > 0 else 3)
PY
}

# need_creds MINUTES [PROFILE] -> 0 if the SSO token outlives MINUTES + OPS_CRED_MARGIN (default 20); else 3.
# A run longer than one SSO session must be resumable in chunks and call need_creds per chunk.
need_creds() {
  [ $# -ge 1 ] || { echo "usage: need_creds MINUTES [PROFILE]" >&2; return 2; }
  local need=$1 prof=${2:-${AWS_PROFILE:-default}} left
  left=$(sso_minutes_left "$prof") || { echo "need_creds: refusing to start (credentials). Run: aws sso login --profile $prof" >&2; return 3; }
  if [ "$left" -lt $(( need + ${OPS_CRED_MARGIN:-20} )) ]; then
    echo "need_creds: SSO for $prof has ${left} min left; this run needs ${need} + ${OPS_CRED_MARGIN:-20} margin. Run: aws sso login --profile $prof" >&2
    return 3
  fi
  echo "need_creds: SSO for $prof ok (${left} min left, need ${need})" >&2
}

# is_auth_error TEXT -> 0 if TEXT looks like dead credentials (stop the run), 1 otherwise.
is_auth_error() {
  printf '%s' "$*" | grep -Eq 'UnauthorizedSSOTokenError|ExpiredToken|TokenRefreshRequired|InvalidClientTokenId|SSOTokenLoadError|The SSO session associated with this profile has expired|refreshed credentials are still expired'
}

# retry N CMD [ARGS...] -> runs CMD up to N times, sleeping OPS_BACKOFF (default "20 40 60") between tries.
# Stops at once (exit 3) on an auth error: retrying dead credentials only hides the problem.
# Returns CMD's stdout only; CMD's stderr goes to stderr (never mixed into the data a caller parses).
retry() {
  [ $# -ge 2 ] || { echo "usage: retry N CMD [ARGS...]" >&2; return 2; }
  local n=$1 i=1 out err ef rc; shift
  local backoff=(${OPS_BACKOFF:-20 40 60})
  ef=$(mktemp "${TMPDIR:-/tmp}/opsretry.XXXXXX") || { echo "retry: mktemp failed" >&2; return 2; }
  while :; do
    out=$("$@" 2>"$ef"); rc=$?; err=$(cat "$ef")
    if [ $rc -eq 0 ]; then
      [ -n "$err" ] && printf '%s\n' "$err" >&2
      rm -f "$ef"; printf '%s' "$out"; return 0
    fi
    is_auth_error "$out
$err" && { printf '%s\n' "$out" "$err" >&2; echo "retry: credentials failed; not retrying" >&2; rm -f "$ef"; return 3; }
    [ $i -ge "$n" ] && { printf '%s\n' "$out" "$err" >&2; rm -f "$ef"; return $rc; }
    sleep "${backoff[$(( i - 1 < ${#backoff[@]} ? i - 1 : ${#backoff[@]} - 1 ))]}"
    i=$((i + 1))
  done
}

# ops_event start|stop|done NAME [LOGFILE] -> a timestamped line bin/measure.py reads for exact stall minutes.
ops_event() {
  printf '%s ops_event %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "${3:-${OPS_EVENT_LOG:-/dev/stderr}}"
}

# --- Bound gos (change 4, off by default; see bin/go.sh) ---------------------------------------------------------
# go_fingerprint SCRIPT [ARGS...] -> sha256 over the script's bytes, its args, the values of the env vars named in
# GO_ENV, and the bytes of the files named in GO_FILES. Hashes CONTENT, so a re-exec'd private copy matches.
go_fingerprint() {
  local s=$1; shift
  {
    printf 'script:'; shasum -a 256 < "$s"
    printf 'args:'; [ $# -gt 0 ] && printf '%s\0' "$@"; printf '\n'   # NUL-separated: ("a b","c") != ("a","b c")
    local v f
    for v in ${GO_ENV:-}; do printf 'env:%s=%s\n' "$v" "${!v-<unset>}"; done
    for f in ${GO_FILES:-}; do printf 'file:%s:' "$f"; shasum -a 256 < "$f"; done
  } | shasum -a 256 | cut -d' ' -f1
}

# require_go [ARGS...] -> call near the top of an ops script, after GO_ENV/GO_FILES are set.
# Returns 0 if the owner recorded a go (bin/go.sh) for exactly this run and it hasn't expired; else 4.
# The go is consumed (one run) unless GO_REUSE=1. Feature flag GO_REQUIRED=1; off by default.
require_go() {
  [ "${GO_REQUIRED:-0}" = 1 ] || return 0
  local fp f dir=${GO_DIR:-$HOME/.claude/gos} exp
  fp=$(go_fingerprint "${GO_SCRIPT:-$0}" "$@"); f="$dir/$fp.go"
  [ -f "$f" ] || { echo "require_go: no go for this exact run (fingerprint ${fp:0:12}). Owner runs: ! ~/.claude/kit/bin/go.sh <script> ..." >&2; return 4; }
  exp=$(sed -n 's/^expires_epoch=//p' "$f")
  { [ -n "$exp" ] && [ "$(date +%s)" -lt "$exp" ]; } || { echo "require_go: the go for ${fp:0:12} has expired" >&2; return 4; }
  [ "${GO_REUSE:-0}" = 1 ] || mv "$f" "$f.used.$(date +%s)"
  echo "require_go: go ${fp:0:12} accepted" >&2
}
