#!/bin/bash
# scan.sh: must catch a planted token, email, key, session-state file and company name, in the tree AND in history,
# and must pass a clean repo (placeholders like you@example.com allowed).
. "$(dirname "$0")/lib.sh"
S=$ROOT/bin/scan.sh
mk() { rm -rf "$TMP/r"; mkdir -p "$TMP/r"; cd "$TMP/r" || exit 1; git init -q -b main; git config user.email t@example.test; git config user.name t; }
commit() { git add -A; git commit -qm c; }

mk; echo "contact: you@example.com; noreply@anthropic.com" > a.md; echo "fine" > b.sh; commit
rc 0 "clean repo passes (placeholders allowed)" /bin/bash "$S" --history "$TMP/r"

fake_gh="ghp_$(printf 'A%.0s' $(seq 1 36))"
mk; echo "token=$fake_gh" > a.sh; commit
rc 1 "planted GitHub token caught" /bin/bash "$S" "$TMP/r"
ok "finding names the rule, not the secret" bash -c "out=\$(/bin/bash '$S' '$TMP/r'); grep -q 'FINDING github-token: a.sh:1' <<<\"\$out\" && ! grep -q '$fake_gh' <<<\"\$out\""

mk; echo "AKIA$(printf 'B%.0s' $(seq 1 16))" > k.txt; commit
rc 1 "planted AWS key caught" /bin/bash "$S" "$TMP/r"
mk; echo "sk-ant-$(printf 'c%.0s' $(seq 1 30))" > k.txt; commit
rc 1 "planted Anthropic key caught" /bin/bash "$S" "$TMP/r"
# Planted values are assembled at runtime so this file itself scans clean.
PK="-----BEGIN OPENSSH PRIV""ATE KEY-----"; EM="jane.doe""@""gmail.com"
mk; printf -- '%s\n' "$PK" > id; commit
rc 1 "planted private key caught" /bin/bash "$S" "$TMP/r"
mk; echo "reach me at $EM" > a.md; commit
rc 1 "planted personal email caught" /bin/bash "$S" "$TMP/r"
mk; mkdir -p hooks/.state; echo x > hooks/.state/verify-1; commit
rc 1 "session state path caught" /bin/bash "$S" "$TMP/r"
mk; mkdir -p projects/p; echo '{}' > projects/p/t.jsonl; commit
rc 1 "transcript path caught" /bin/bash "$S" "$TMP/r"

# History: a secret committed then deleted is still found with --history, not without.
mk; echo "token=$fake_gh" > a.sh; commit; git rm -q a.sh; echo ok > b.md; commit
rc 0 "deleted secret not in the tree" /bin/bash "$S" "$TMP/r"
rc 1 "deleted secret found in history" /bin/bash "$S" --history "$TMP/r"
mk; echo "$EM" > a.md; commit; echo clean > a.md; commit
rc 1 "deleted email found in history" /bin/bash "$S" --history "$TMP/r"

# Name list (for the friend's kit)
printf 'acme-corp\nsecret-project\n' > "$TMP/names"
mk; echo "built for Acme-Corp" > a.md; commit
rc 1 "planted company name caught (case-insensitive)" /bin/bash "$S" --names "$TMP/names" "$TMP/r"
mk; mkdir -p secret-project; echo x > secret-project/a; commit
rc 1 "company name in a path caught" /bin/bash "$S" --names "$TMP/names" "$TMP/r"
mk; echo "generic text" > a.md; commit
rc 0 "no names: clean" /bin/bash "$S" --names "$TMP/names" --history "$TMP/r"
rc 2 "not a git repo: error" /bin/bash "$S" "$TMP"
# Review finding: a relative --names path must still be read (it used to be read after cd, and "pass").
mk; echo "built for Acme-Corp" > a.md; commit
cp "$TMP/names" "$TMP/r/../rel-names.txt"
rc 1 "relative --names path is resolved and used" bash -c "cd '$TMP' && /bin/bash '$S' --names rel-names.txt '$TMP/r'"
rc 2 "unreadable --names file is an error, not a pass" /bin/bash "$S" --names "$TMP/no-such-file" "$TMP/r"
: > "$TMP/empty-names"; rc 2 "an empty --names file is an error" /bin/bash "$S" --names "$TMP/empty-names" "$TMP/r"
rc 2 "a directory as --names is an error" /bin/bash "$S" --names "$TMP" "$TMP/r"
echo '(unclosed' > "$TMP/bad-names"; rc 2 "an invalid pattern in --names is an error" /bin/bash "$S" --names "$TMP/bad-names" "$TMP/r"
rc 2 "--names with no value is a usage error" /bin/bash "$S" "$TMP/r" --names

# finds WANT CMD...: CMD exits 1 and its output holds WANT (a rule name + location, so the test fails without that rule).
finds() { local want=$1 out; shift; out=$("$@" 2>/dev/null); [ $? = 1 ] && grep -qF -- "$want" <<<"$out"; }
rep() { local s="" i=0; while [ $i -lt "$2" ]; do s="$s$1"; i=$((i+1)); done; printf '%s' "$s"; }
# caught RULE VALUE: VALUE planted in k.txt is reported by RULE itself, not by some other rule.
caught() { mk; printf '%s\n' "$2" > k.txt; commit; ok "planted $1 caught by its own rule" finds "FINDING $1: k.txt:1" /bin/bash "$S" "$TMP/r"; }
# Security-review rules. Every value is assembled from fragments so this file scans clean.
caught aws-secret "AWS_SECRET""_ACCESS_KEY=$(rep A 20)/$(rep b 19)"
caught gcp-api-key "AI""za$(rep B 35)"
caught gcp-oauth "GOC""SPX-$(rep c 24)"
caught azure-key "DefaultEndpointsProtocol=https;AccountKey=$(rep d 86)""=="
caught azure-sas "https://x.blob.core.windows.net/c/f?sv=2022-11-02&s""ig=$(rep e 30)"
caught jwt "ey""J$(rep f 12).ey""J$(rep g 12).$(rep h 12)"
caught stripe "sk_li""ve_$(rep i 24)"
caught npm-token "//registry.npmjs.org/:_auth""Token=$(rep j 8)"
caught npm-token "np""m_$(rep k 36)"
caught pypi "pypi-AgEIcHlwaS5v""cmc$(rep l 24)"
caught key-other "-----BEGIN PGP PRIV""ATE KEY BLOCK-----"
caught key-other "PuTTY-User-Key-File-""3: ssh-ed25519"
caught gitlab "glp""at-$(rep m 20)"
caught slack-hook "https://hooks.sl""ack.com/services/T$(rep 0 9)/B$(rep 1 9)/$(rep n 24)"
U=admin; P=hunter22; H=db.internal; caught url-creds "postgres://$U:$P@$H/app"
caught sendgrid "S""G.$(rep o 22).$(rep p 43)"
caught generic-unquoted "api_key: $(rep q 24)"

# Paths with spaces and non-ASCII names are scanned (git ls-files used to quote or split them).
mk; echo "token=$fake_gh" > "a b.txt"; commit
ok "planted key in a path with a space caught" finds "FINDING github-token: a b.txt:1" /bin/bash "$S" "$TMP/r"
mk; echo "token=$fake_gh" > "café.txt"; commit
ok "planted key in a non-ASCII path caught" finds "FINDING github-token: café.txt:1" /bin/bash "$S" "$TMP/r"
mk; mkdir "dir x"; echo "token=$fake_gh" > "dir x/a b.txt"; commit; git rm -q "dir x/a b.txt"; echo ok > c.md; commit
ok "deleted secret in a path with spaces found in history" finds "FINDING github-token: history:dir x/a b.txt@" /bin/bash "$S" --history "$TMP/r"

# Commit metadata with --history: message bodies and author/committer emails.
mk; echo ok > a.md; git add -A; git commit -qm "deploy with token $fake_gh"
rc 0 "token in a commit message: not in the tree" /bin/bash "$S" "$TMP/r"
ok "token in a commit message found in history" finds "FINDING github-token: history:commit-message@" /bin/bash "$S" --history "$TMP/r"
mk; echo ok > a.md; git add -A; git -c user.email="$EM" commit -qm c
ok "personal author email found in history" finds "FINDING commit-email: history:commit@" /bin/bash "$S" --history "$TMP/r"
mk; echo ok > a.md; git add -A
git -c user.email=12345+t@users.noreply.github.com commit -qm "c

Co-Authored-By: Claude <noreply@anthropic.com>"
rc 0 "noreply author email and attribution trailer are fine" /bin/bash "$S" --history "$TMP/r"
finish
