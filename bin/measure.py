#!/usr/bin/env python3
"""Before/after numbers for the agent setup. Read-only. Rerun any time; compare runs by date.

  measure.py --since 2026-10-06 --repos owner/a owner/b --logs DIR [DIR...] [--gh-account NAME] [--json]

1. SSO-killed runs: run-log files (*.log, *stderr*) whose text holds a credential-expiry error, per day of file mtime.
2. Merge wait: minutes from a PR's last "VERIFIED <sha>" comment to its merge, p50/p90/max, per repo.
3. Overnight stall minutes (00:00-08:00 local): in logs with "== <ISO> <name> start" headers, the time from a run
   that ended STOPPED to the next start of the same script. An UPPER bound for old logs (the stop time isn't
   logged); exact for scripts that log `ops_event stop` lines (opslib), which this reads when present.
Prints counts only: no file contents, keys or tokens.
"""
import argparse, json, os, re, statistics, subprocess
from collections import defaultdict
from datetime import datetime, timezone, timedelta

AUTH = re.compile(rb"UnauthorizedSSOTokenError|ExpiredToken|TokenRefreshRequired|SSOTokenLoadError|"
                  rb"refreshed credentials are still expired|SSO session associated with this profile has expired")
HEAD = re.compile(r"^== (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) (\S+) start")
EVENT = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) ops_event (start|stop|done) (\S+)")

def iso(s): return datetime.fromisoformat(s.replace("Z", "+00:00"))

def log_files(dirs):
    for d in dirs:
        for root, _, files in os.walk(os.path.expanduser(d)):
            for f in files:
                if f.endswith(".log") or "stderr" in f or f.endswith(".out"):
                    yield os.path.join(root, f)

def sso_killed(dirs, since):
    per_day = defaultdict(int)
    for p in log_files(dirs):
        try:
            st = os.stat(p)
            if datetime.fromtimestamp(st.st_mtime, timezone.utc) < since or st.st_size > 50_000_000:
                continue
            if AUTH.search(open(p, "rb").read()):
                per_day[datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d")] += 1
        except OSError:
            continue
    return dict(sorted(per_day.items()))

def overnight_minutes(start, end):
    """Minutes of [start, end) that fall between 00:00 and 08:00 local time."""
    total, t = 0, start.astimezone()
    end = end.astimezone()
    while t < end:
        nxt = min(end, t + timedelta(minutes=1))
        if t.hour < 8:
            total += (nxt - t).total_seconds() / 60
        t = nxt
    return total

def stalls(dirs, since):
    exact, upper, n = 0.0, 0.0, 0
    for p in log_files(dirs):
        try:
            lines = open(p, errors="replace").read().splitlines()
        except OSError:
            continue
        runs, events = [], []
        for ln in lines:
            m = HEAD.match(ln)
            if m: runs.append([iso(m.group(1)), m.group(2), False])
            elif runs and ln.startswith("STOPPED"): runs[-1][2] = True
            e = EVENT.match(ln)
            if e: events.append((iso(e.group(1)), e.group(2), e.group(3)))
        for (t0, name, stopped), nxt in zip(runs, runs[1:]):
            if stopped and t0 >= since and nxt[1] == name:
                upper += overnight_minutes(t0, nxt[0]); n += 1
        last_stop = {}
        for t, kind, name in events:
            if t < since: continue
            if kind == "stop": last_stop[name] = t
            elif kind == "start" and name in last_stop:
                exact += overnight_minutes(last_stop.pop(name), t)
    return {"stopped_runs_restarted": n, "upper_bound_min": round(upper), "exact_min_from_ops_events": round(exact)}

def merge_waits(repos, since, account):
    env = dict(os.environ)
    if account:
        env["GH_TOKEN"] = subprocess.check_output(["gh", "auth", "token", "-u", account], text=True).strip()
    out = {}
    for repo in repos:
        prs = json.loads(subprocess.check_output(
            ["gh", "pr", "list", "-R", repo, "--state", "merged", "--limit", "300", "--json", "number,mergedAt,comments"], env=env))
        waits = []
        for p in prs:
            if not p["mergedAt"] or iso(p["mergedAt"]) < since: continue
            v = [c["createdAt"] for c in p["comments"] if c["body"].lstrip().startswith("VERIFIED")]
            if v:
                w = (iso(p["mergedAt"]) - iso(max(v))).total_seconds() / 60
                if w >= 0: waits.append(w)
        waits.sort(); n = len(waits)
        out[repo] = {"n": n} if not n else {
            "n": n, "p50_min": round(statistics.median(waits)), "p90_min": round(waits[min(n - 1, int(n * .9))]),
            "max_min": round(waits[-1]), "total_h": round(sum(waits) / 60, 1)}
    return out

def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--since", required=True); a.add_argument("--repos", nargs="*", default=[])
    a.add_argument("--logs", nargs="*", default=[]); a.add_argument("--gh-account"); a.add_argument("--json", action="store_true")
    o = a.parse_args()
    since = datetime.fromisoformat(o.since).replace(tzinfo=timezone.utc)
    r = {"measured_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "since": o.since,
         "sso_killed_runs_by_day": sso_killed(o.logs, since) if o.logs else "no --logs",
         "overnight_stall": stalls(o.logs, since) if o.logs else "no --logs",
         "merge_wait": merge_waits(o.repos, since, o.gh_account) if o.repos else "no --repos"}
    print(json.dumps(r, indent=None if o.json else 2))

if __name__ == "__main__":
    main()
