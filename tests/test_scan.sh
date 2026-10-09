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
finish
