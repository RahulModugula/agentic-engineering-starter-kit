#!/bin/bash
# opslib: every helper must fire when its condition holds AND fail when it doesn't.
. "$(dirname "$0")/lib.sh"
. "$ROOT/claude/lib/opslib.sh"
OPS_POLL=0.1

# wait_marker
( sleep 0.3; touch "$TMP/m" ) &
rc 0 "wait_marker fires when the marker appears" wait_marker "$TMP/m" 5
rc 124 "wait_marker times out when no marker" wait_marker "$TMP/never" 1
rc 2 "wait_marker usage error" wait_marker "$TMP/m"

# wait_log
: > "$TMP/log"; ( sleep 0.3; echo "step 4 DONE ok" >> "$TMP/log" ) &
rc 0 "wait_log fires on a matching line" wait_log "$TMP/log" 'DONE' 5
rc 124 "wait_log times out without a match" wait_log "$TMP/log" 'NEVER-PRINTED' 1
echo "old DONE" > "$TMP/log2"
OPS_FROM_END=1 rc 124 "wait_log OPS_FROM_END ignores old lines" wait_log "$TMP/log2" 'DONE' 1
# Regression for the 10-08 failure: a pattern that appears in the watcher's OWN command line must not satisfy it.
rc 124 "watcher cannot match itself (no process table)" wait_log "$TMP/empty-$$" 'wait_log' 1

# launch / alive / stop_own
pid=$(launch "$TMP/p.pid" sleep 30)
ok "alive true for a launched process" alive "$TMP/p.pid"
ok "stop_own stops it" stop_own "$TMP/p.pid"
sleep 0.3
no "alive false after it stops" alive "$TMP/p.pid"
printf '%s\t%s\n' "$$" "Thu Jan  1 00:00:00 1970" > "$TMP/reuse.pid"
no "alive false when the PID was reused (start time differs)" alive "$TMP/reuse.pid"
no "alive false for a missing pidfile" alive "$TMP/nope.pid"
echo "garbage" > "$TMP/bad.pid"; no "alive false for a corrupt pidfile" alive "$TMP/bad.pid"
# A live PID with NO recorded start time can't be told from a stranger that reused it: not alive.
printf '%s\t\n' "$$" > "$TMP/nost.pid"; no "alive false when the pidfile has no start time" alive "$TMP/nost.pid"
printf '%s\n' "$$" > "$TMP/nost2.pid"; no "alive false for a bare-PID pidfile" alive "$TMP/nost2.pid"
printf '%s\t%s\n' "$$" "$(_ops_start_time $$)" > "$TMP/self.pid"; ok "alive true when PID and start time match" alive "$TMP/self.pid"

# need_creds / sso_minutes_left against a fake config + cache (no real tokens touched)
mkdir -p "$TMP/cache"
cat > "$TMP/config" <<'EOF'
[profile legacy]
sso_start_url = https://example.test/start
sso_region = us-east-1
[profile modern]
sso_session = s1
[sso-session s1]
sso_start_url = https://example.test/start2
sso_region = us-east-1
[profile plain]
region = us-east-1
EOF
exp() { /usr/bin/python3 -c "import datetime as d;print((d.datetime.now(d.timezone.utc)+d.timedelta(minutes=$1)).strftime('%Y-%m-%dT%H:%M:%SZ'))"; }
printf '{"startUrl":"https://example.test/start","expiresAt":"%s","accessToken":"x"}' "$(exp 120)" > "$TMP/cache/a.json"
printf '{"startUrl":"https://example.test/start2","expiresAt":"%s","accessToken":"x"}' "$(exp 30)" > "$TMP/cache/b.json"
export AWS_CONFIG_FILE="$TMP/config" OPS_SSO_CACHE="$TMP/cache"
rc 0 "need_creds passes with 120 min left, 60 needed" need_creds 60 legacy
rc 3 "need_creds refuses with 120 min left, 110 needed (+20 margin)" need_creds 110 legacy
rc 0 "need_creds reads sso-session profiles" need_creds 5 modern
rc 3 "need_creds refuses when token is short (sso-session)" need_creds 20 modern
rc 3 "need_creds refuses a non-SSO profile" need_creds 5 plain
rc 3 "need_creds refuses an unknown profile" need_creds 5 ghost
printf '{"startUrl":"https://example.test/start","expiresAt":"%s","accessToken":"x"}' "$(exp -5)" > "$TMP/cache/a.json"
rc 3 "need_creds refuses an expired token" need_creds 1 legacy
# sso-session: a 50-min access token that refreshes, plus a sign-in record 2 h ago (8 h session -> 6 h left)
printf '{"startUrl":"https://example.test/start2","expiresAt":"%s","accessToken":"x","refreshToken":"r"}' "$(exp 50)" > "$TMP/cache/b.json"
export OPS_SSO_LOGIN_DIR="$TMP/logins"
rc 3 "refreshable session without a sign-in record: refused (fail closed)" need_creds 30 modern
mkdir -p "$OPS_SSO_LOGIN_DIR"
echo $(( $(date +%s) - 7200 )) > "$OPS_SSO_LOGIN_DIR/$(printf '%s' https://example.test/start2 | shasum -a 1 | cut -d' ' -f1)"
rc 0 "refreshable session: 120-min run passes on 6 h left despite a 50-min token" need_creds 120 modern
rc 3 "refreshable session: 400-min run refused (6 h left)" need_creds 400 modern
OPS_SSO_SESSION_HOURS=2 rc 3 "shorter configured session is honoured" need_creds 10 modern
unset AWS_CONFIG_FILE OPS_SSO_CACHE OPS_SSO_LOGIN_DIR

# is_auth_error / retry
ok "is_auth_error: SSO expiry" is_auth_error "botocore.exceptions.UnauthorizedSSOTokenError: The SSO session ..."
ok "is_auth_error: expired token" is_auth_error "An error occurred (ExpiredToken) when calling"
no "is_auth_error: a network error is not auth" is_auth_error "EndpointConnectionError: Could not connect"
OPS_BACKOFF="0 0 0"
echo 0 > "$TMP/n"; flaky() { local n; n=$(($(cat "$TMP/n")+1)); echo $n > "$TMP/n"; [ $n -ge 3 ]; }
rc 0 "retry succeeds on the 3rd try" retry 3 flaky
echo 0 > "$TMP/n"; rc 1 "retry gives up after N tries" retry 2 flaky
dead() { echo "UnauthorizedSSOTokenError"; return 1; }
echo 0 > "$TMP/n"; cnt() { echo $(( $(cat "$TMP/n") + 1 )) > "$TMP/n"; dead; }
rc 3 "retry stops at once on an auth error" retry 3 cnt
eq "retry did not repeat an auth failure" "$(cat "$TMP/n")" "1"
# stdout is the data; a warning on stderr must not end up in it (but still reaches stderr).
noisy() { echo "warning: slow" >&2; echo '{"ok":1}'; }
eq "retry returns only the command's stdout" "$(retry 2 noisy 2>/dev/null)" '{"ok":1}'
ok "retry passes the command's stderr through" grep -q "warning: slow" <<<"$(retry 2 noisy 2>&1 >/dev/null)"
dead2() { echo "UnauthorizedSSOTokenError" >&2; return 1; }
rc 3 "retry still sees an auth error printed on stderr" retry 3 dead2

# go_fingerprint: arguments are hashed NUL-separated, so word boundaries count.
printf 'echo hi\n' > "$TMP/s.sh"
a=$(go_fingerprint "$TMP/s.sh" "a b" c); b=$(go_fingerprint "$TMP/s.sh" a "b c")
no "go_fingerprint: (\"a b\",\"c\") differs from (\"a\",\"b c\")" test "$a" = "$b"
eq "go_fingerprint: same args, same fingerprint" "$(go_fingerprint "$TMP/s.sh" "a b" c)" "$a"

# No process-pattern tools anywhere in the library (the 10-07/10-08 failures).
no "opslib uses no pgrep/pkill/killall" grep -Eq '^[^#]*\b(pgrep|pkill|killall)\b' "$ROOT/claude/lib/opslib.sh"
finish
