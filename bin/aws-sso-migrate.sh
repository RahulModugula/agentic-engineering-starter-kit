#!/bin/bash
# aws-sso-migrate.sh [--write]: convert legacy SSO profiles (sso_start_url in each profile, a token that can't be
# refreshed) to the recommended [sso-session] form (the SDK can refresh within the session).
# Default: print the proposed config. --write: back up the file to <file>.bak-<time>, then write it.
# Profiles that share a start URL + region share one sso-session. Non-SSO profiles are untouched. Prints no tokens.
# After --write, run `aws sso login --sso-session <name>` once.
set -euo pipefail
CFG=${AWS_CONFIG_FILE:-$HOME/.aws/config}
mode=${1:-dry}
/usr/bin/python3 - "$CFG" "$mode" <<'PY'
import configparser, io, shutil, sys, time
path, mode = sys.argv[1], sys.argv[2]
cfg = configparser.RawConfigParser(); cfg.optionxform = str; cfg.read(path)
sessions, changed = {}, []
for sec in cfg.sections():
    if not sec.startswith("profile ") and sec != "default":
        continue
    p = cfg[sec]
    if "sso_start_url" not in p or "sso_session" in p:
        continue
    key = (p["sso_start_url"], p.get("sso_region", "us-east-1"))
    name = sessions.setdefault(key, f"sso{len(sessions) + 1}" if len(sessions) else "sso")
    del p["sso_start_url"]
    if "sso_region" in p: del p["sso_region"]
    p["sso_session"] = name
    changed.append(sec)
for (url, region), name in sessions.items():
    s = f"sso-session {name}"
    if not cfg.has_section(s):
        cfg.add_section(s)
        cfg[s]["sso_start_url"] = url; cfg[s]["sso_region"] = region
        cfg[s]["sso_registration_scopes"] = "sso:account:access"
buf = io.StringIO(); cfg.write(buf)
if not changed:
    print("aws-sso-migrate: nothing to change (no legacy SSO profiles)."); sys.exit(0)
print(f"aws-sso-migrate: {len(changed)} legacy profile(s) -> {len(sessions)} sso-session(s): {', '.join(changed)}")
if mode != "--write":
    print("DRY RUN. Note: --write drops comments in the file (the backup keeps them).")
    print("It also does not lengthen the session by itself: that is the Identity Center session duration setting.")
    print("Proposed config (start URLs shown as <url>):")
    out = buf.getvalue()
    for (url, _), _n in sessions.items(): out = out.replace(url, "<url>")
    print(out); sys.exit(0)
bak = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}"; shutil.copy2(path, bak)
open(path, "w").write(buf.getvalue())
print(f"Wrote {path} (backup {bak}). Next: aws sso login --sso-session {next(iter(sessions.values()))}")
PY
