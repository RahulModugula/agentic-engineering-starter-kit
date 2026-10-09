#!/bin/bash
# measure.py: counts SSO-killed logs and overnight stalls correctly, and ignores files that don't qualify.
. "$(dirname "$0")/lib.sh"
mkdir -p "$TMP/logs"
echo "botocore.exceptions.UnauthorizedSSOTokenError: x" > "$TMP/logs/a-stderr.log"
echo "EndpointConnectionError (retried)" > "$TMP/logs/b.log"
echo "ExpiredToken when calling" > "$TMP/logs/c.log"
echo "UnauthorizedSSOTokenError" > "$TMP/logs/notes.txt"     # not a log file: ignored
# Two runs of job-1: the first STOPPED at 01:00Z-ish; the second started 02:00Z. Plus exact ops_events.
cat > "$TMP/logs/run.log" <<'EOF'
== 2030-01-02T06:00:00Z job-1 start
STOPPED: release did not verify
== 2030-01-02T07:00:00Z job-1 start
2030-01-02T06:10:00Z ops_event stop job-2
2030-01-02T06:40:00Z ops_event start job-2
EOF
out=$(TZ=UTC python3 "$ROOT/bin/measure.py" --since 2000-01-01 --logs "$TMP/logs" --json)
eq "two SSO-killed logs counted (not the retried one or the .txt)" "$(jq '[.sso_killed_runs_by_day[]]|add' <<<"$out")" "2"
eq "one STOPPED-then-restarted run" "$(jq '.overnight_stall.stopped_runs_restarted' <<<"$out")" "1"
eq "upper bound = 60 overnight minutes (06:00-07:00 UTC)" "$(jq '.overnight_stall.upper_bound_min' <<<"$out")" "60"
eq "exact ops_event stall = 30 min" "$(jq '.overnight_stall.exact_min_from_ops_events' <<<"$out")" "30"
out=$(TZ=UTC python3 "$ROOT/bin/measure.py" --since 2031-01-01 --logs "$TMP/logs" --json)
eq "since filter excludes older runs" "$(jq '.overnight_stall.stopped_runs_restarted' <<<"$out")" "0"
# ops_event writes the format measure.py reads
. "$ROOT/claude/lib/opslib.sh"; ops_event stop job-x "$TMP/logs/ev.log"
ok "ops_event line format" grep -Eq '^[0-9T:-]+Z ops_event stop job-x$' "$TMP/logs/ev.log"
finish
