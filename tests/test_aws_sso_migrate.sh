#!/bin/bash
# aws-sso-migrate: dry run changes nothing; --write converts legacy profiles, keeps a backup, leaves others alone.
. "$(dirname "$0")/lib.sh"
M=$ROOT/bin/aws-sso-migrate.sh
cat > "$TMP/config" <<'EOF'
[profile a]
sso_start_url = https://example.test/start
sso_region = us-east-1
sso_account_id = 111111111111
sso_role_name = R
region = us-east-1

[profile b]
sso_start_url = https://example.test/start
sso_region = us-east-1
sso_account_id = 222222222222
sso_role_name = R

[profile plain]
region = us-east-1
EOF
cp "$TMP/config" "$TMP/orig"
out=$(AWS_CONFIG_FILE="$TMP/config" /bin/bash "$M")
ok "dry run reports both legacy profiles" grep -q "2 legacy profile(s) -> 1 sso-session" <<<"$out"
ok "dry run hides the start URL" bash -c "! grep -q example.test <<<\"\$1\"" _ "$out"
ok "dry run leaves the file unchanged" cmp -s "$TMP/config" "$TMP/orig"
AWS_CONFIG_FILE="$TMP/config" /bin/bash "$M" --write >/dev/null
ok "write keeps a backup" bash -c "ls $TMP/config.bak-* >/dev/null"
ok "profiles now use sso_session" grep -q "^sso_session = sso$" "$TMP/config"
no "no profile keeps sso_start_url outside the session" bash -c "awk '/^\[profile/{p=1} /^\[sso-session/{p=0} p&&/sso_start_url/' $TMP/config | grep -q ."
ok "plain profile untouched" grep -q "^\[profile plain\]" "$TMP/config"
# the opslib preflight reads the migrated form
. "$ROOT/claude/lib/opslib.sh"; mkdir -p "$TMP/c"
printf '{"startUrl":"https://example.test/start","expiresAt":"2999-01-01T00:00:00Z","accessToken":"x"}' > "$TMP/c/t.json"
AWS_CONFIG_FILE="$TMP/config" OPS_SSO_CACHE="$TMP/c" rc 0 "need_creds works after migration" need_creds 60 a
out=$(AWS_CONFIG_FILE="$TMP/config" /bin/bash "$M")
ok "second run: nothing to change" grep -q "nothing to change" <<<"$out"
finish
