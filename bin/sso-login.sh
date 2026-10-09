#!/bin/bash
# sso-login.sh PROFILE: `aws sso login`, then record WHEN you signed in, so need_creds (opslib.sh) can tell how long the
# session has left. Under [sso-session] config the token cache only shows an hourly, self-refreshing token; the session
# itself ends OPS_SSO_SESSION_HOURS (default 8, your Identity Center setting) after sign-in. Prints no tokens.
set -euo pipefail
P=${1:?usage: sso-login.sh PROFILE}
aws sso login --profile "$P"
start=$(/usr/bin/python3 - "$P" "${AWS_CONFIG_FILE:-$HOME/.aws/config}" <<'PY'
import configparser, sys
p, path = sys.argv[1:3]
c = configparser.RawConfigParser(); c.read(path)
s = "default" if p == "default" else f"profile {p}"
sess = c.get(s, "sso_session", fallback=None)
print(c.get(f"sso-session {sess}", "sso_start_url") if sess else c.get(s, "sso_start_url"))
PY
)
d=${OPS_SSO_LOGIN_DIR:-$HOME/.aws/sso/login-times}; mkdir -p "$d"; chmod 700 "$d"
date +%s > "$d/$(printf '%s' "$start" | shasum -a 1 | cut -d' ' -f1)"
echo "Signed in; session recorded (expect about ${OPS_SSO_SESSION_HOURS:-8} h)."
