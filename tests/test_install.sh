#!/bin/bash
# install.sh in a sandbox: dry run changes nothing; apply links program files, MERGES settings (keeps yours), adds
# one CLAUDE.md import line, copies config only if missing; rollback restores byte-for-byte; status detects drift.
. "$(dirname "$0")/lib.sh"
CH=$TMP/home/.claude; export CLAUDE_HOME=$CH INSTALL_BACKUPS=$TMP/home/.claude-backups MERGE_STATE=$TMP/ms
mkdir -p "$CH/hooks/.state" "$CH/projects/p" "$CH/roles"
cat > "$CH/settings.json" <<'EOF'
{"model": "my-model", "permissions": {"deny": ["Read(~/mine/**)"]},
 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "~/my-stop.sh"}]}]}}
EOF
printf 'My own rules.\n' > "$CH/CLAUDE.md"
echo "old lane role" > "$CH/roles/lane.md"
echo "MY_CONF=1" > "$CH/guard.conf"
echo "session state" > "$CH/hooks/.state/verify-x"
echo "transcript" > "$CH/projects/p/t.jsonl"
snap() { (cd "$CH" && find . -type f | sort | xargs shasum) > "$1"; }
snap "$TMP/before.sha"
I="$ROOT/install.sh"
mkdir -p "$TMP/fb"; printf '#!/bin/bash\necho "${FAKE_CLAUDE_VER:-2.1.295} (Claude Code)"\n' > "$TMP/fb/claude"; chmod +x "$TMP/fb/claude"
export PATH="$TMP/fb:$PATH"
KIT=$ROOT/claude/settings.json
# In the source repo claude/settings.json is the maintainer's own; the shipped kit's is kit/claude/settings.json.
[ -f "$ROOT/kit/claude/settings.json" ] && KIT=$ROOT/kit/claude/settings.json
export KIT_SETTINGS=$KIT

out=$(/bin/bash "$I")
ok "dry run shows the settings merge" grep -q "~ MERGE settings.json" <<<"$out"
ok "dry run lists a new program file" grep -q "+ NEW   lib/opslib.sh" <<<"$out"
ok "dry run lists the CLAUDE.md import" grep -q "+ LINE  CLAUDE.md" <<<"$out"
ok "dry run lists the kit link" grep -q "+ LINK  kit" <<<"$out"
snap "$TMP/after-dry.sha"
ok "dry run changed nothing" cmp -s "$TMP/before.sha" "$TMP/after-dry.sha"

FAKE_CLAUDE_VER=2.1.200 /bin/bash "$I" > "$TMP/old.out"
ok "an old Claude Code only warns" grep -q "older than 2.1.290" "$TMP/old.out"
/bin/bash "$I" --apply > "$TMP/apply.out"
ok "settings.json stays a plain file (not a symlink)" test -f "$CH/settings.json" -a ! -L "$CH/settings.json"
eq "your own setting is kept" "$(jq -r .model "$CH/settings.json")" "my-model"
ok "your own deny rule is kept" jq -e '.permissions.deny | index("Read(~/mine/**)")' "$CH/settings.json"
ok "your own hook is kept" jq -e '[.hooks.Stop[].hooks[].command] | index("~/my-stop.sh")' "$CH/settings.json"
ok "every kit deny rule is added" python3 "$ROOT/bin/settings-merge.py" check "$CH/settings.json" "$KIT"
ok "the guard hook is registered" jq -e '[.hooks.PreToolUse[].hooks[].command] | index("~/.claude/hooks/lane-guard.sh")' "$CH/settings.json"
ok "CLAUDE.md keeps your text" grep -q "My own rules." "$CH/CLAUDE.md"
ok "CLAUDE.md gets the import line" grep -qxF '@~/.claude/kit/claude/CLAUDE.md' "$CH/CLAUDE.md"
eq "kit links to the repo" "$(readlink "$CH/kit")" "$ROOT"
ok "a hook is linked" test -L "$CH/hooks/lane-guard.sh"
eq "your own role file is kept as it is (roles are yours, not the kit's)" "$(cat "$CH/roles/lane.md")" "old lane role"
ok "a role you don't have is copied in" test -f "$CH/roles/coordinator.md" -a ! -L "$CH/roles/coordinator.md"
eq "your guard.conf is not replaced" "$(cat "$CH/guard.conf")" "MY_CONF=1"
ok "lanes.zsh is copied when missing" test -f "$CH/lanes.zsh" -a ! -L "$CH/lanes.zsh"
ok "apply leaves hooks/.state alone" grep -q "session state" "$CH/hooks/.state/verify-x"
ok "apply leaves projects/ alone" test -f "$CH/projects/p/t.jsonl" -a ! -L "$CH/projects/p/t.jsonl"
ok "status OK after apply" /bin/bash "$I" --status
ok "dry run after apply: nothing to change" grep -q "^0 change(s) would be made" <<<"$(/bin/bash "$I")"

/bin/bash "$I" --apply >/dev/null
eq "a second apply adds no duplicate import" "$(grep -c 'kit/claude/CLAUDE.md' "$CH/CLAUDE.md")" 1
eq "a second apply adds no duplicate hook" "$(jq '[.hooks.PreToolUse[].hooks[].command] | map(select(. == "~/.claude/hooks/lane-guard.sh")) | length' "$CH/settings.json")" 1
/bin/bash "$I" --rollback >/dev/null

cp "$CH/settings.json" "$TMP/s.json"; jq '.permissions.deny = []' "$TMP/s.json" > "$CH/settings.json"
no "status detects removed deny rules" /bin/bash "$I" --status
cp "$TMP/s.json" "$CH/settings.json"
rm "$CH/hooks/lane-guard.sh"; echo "edited" > "$CH/hooks/lane-guard.sh"
no "status detects a link replaced by a plain file" /bin/bash "$I" --status

/bin/bash "$I" --rollback >/dev/null
snap "$TMP/after-rb.sha"
ok "rollback restores every original file byte-for-byte" cmp -s "$TMP/before.sha" "$TMP/after-rb.sha"
no "rollback removes files that didn't exist before" test -e "$CH/lib/opslib.sh"
no "rollback removes the kit link" test -e "$CH/kit"
ok "rollback leaves no stray symlinks" test -z "$(find "$CH" -type l)"
eq "rollback leaves no empty folders it created" "$(find "$CH" -type d -empty | sed "s#^$CH/##")" ""
rc 1 "no unused backup left" /bin/bash "$I" --rollback

# Apply twice "in the same second" (a fake date), roll back twice: backups must sort in the order they were made.
mkdir -p "$TMP/samesec"; printf '#!/bin/bash\necho 20300101-000000\n' > "$TMP/samesec/date"; chmod +x "$TMP/samesec/date"
PATH="$TMP/samesec:$PATH" /bin/bash "$I" --apply >/dev/null; PATH="$TMP/samesec:$PATH" /bin/bash "$I" --apply >/dev/null
/bin/bash "$I" --rollback >/dev/null
ok "first rollback undoes only the second apply: links stay" test -L "$CH/hooks/lane-guard.sh"
/bin/bash "$I" --rollback >/dev/null
snap "$TMP/after-rb2.sha"
ok "apply x2 + rollback x2 restores the originals" cmp -s "$TMP/before.sha" "$TMP/after-rb2.sha"

# A settings.json we can't parse is never overwritten.
cp "$CH/settings.json" "$TMP/good.json"; echo "{not json" > "$CH/settings.json"
rc 1 "apply refuses an unparseable settings.json" /bin/bash "$I" --apply
eq "the unparseable file is untouched" "$(cat "$CH/settings.json")" "{not json"
no "the refused apply linked nothing" test -e "$CH/kit"
cp "$TMP/good.json" "$CH/settings.json"

# A settings.json that is a symlink (e.g. into a dotfiles repo): replaced by the merged file, target untouched.
mkdir -p "$TMP/dot"; cp "$TMP/good.json" "$TMP/dot/settings.json"; rm "$CH/settings.json"; ln -s "$TMP/dot/settings.json" "$CH/settings.json"
/bin/bash "$I" --apply >/dev/null
ok "the symlink's target is not written through" cmp -s "$TMP/dot/settings.json" "$TMP/good.json"
/bin/bash "$I" --rollback >/dev/null
eq "rollback restores the symlink" "$(readlink "$CH/settings.json")" "$TMP/dot/settings.json"

# No settings.json and no CLAUDE.md at all: both are created.
rm "$CH/settings.json" "$CH/CLAUDE.md"
/bin/bash "$I" --apply >/dev/null
ok "fresh settings.json has the kit rules" python3 "$ROOT/bin/settings-merge.py" check "$CH/settings.json" "$KIT"
eq "fresh CLAUDE.md is just the import" "$(cat "$CH/CLAUDE.md")" '@~/.claude/kit/claude/CLAUDE.md'
/bin/bash "$I" --rollback >/dev/null
no "rollback removes the created settings.json" test -e "$CH/settings.json"

# merge-queue migration: copies the old inline list, leaves the old script alone
cp "$TMP/good.json" "$CH/settings.json"
mkdir -p "$TMP/old"; printf 'x\nwhile read R P H N; do :; done <<LIST\n# o/r 1 a\no/r 2 b\nLIST\n' > "$TMP/old/merge_next.sh"
echo "o/r 2 b" > "$TMP/old/verified.txt"; cp "$TMP/old/merge_next.sh" "$TMP/old.copy"
OLD_MERGE_DIR=$TMP/old /bin/bash "$I" --apply >/dev/null
eq "queue migrated (commented line kept as comment)" "$(cat "$TMP/ms/queue.txt")" "$(printf '# o/r 1 a\no/r 2 b')"
ok "verified.txt copied" cmp -s "$TMP/old/verified.txt" "$TMP/ms/verified.txt"
ok "old merge script untouched" cmp -s "$TMP/old/merge_next.sh" "$TMP/old.copy"
/bin/bash "$I" --rollback >/dev/null
rc 2 "unknown flag prints usage" /bin/bash "$I" --bogus
# onFailure ("block" when a guard can't run) only for Claude Code >= 2.1.295; a later apply adds it after an update.
cp "$TMP/good.json" "$CH/settings.json"
FAKE_CLAUDE_VER=2.1.280 /bin/bash "$I" --apply >/dev/null
eq "old Claude Code: guard hook has no onFailure" "$(jq -r '[.hooks.PreToolUse[].hooks[] | select(.command|endswith("lane-guard.sh")) | .onFailure] | first // "none"' "$CH/settings.json")" none
FAKE_CLAUDE_VER=2.1.280 ok "old Claude Code: status still OK" /bin/bash "$I" --status
no "after updating Claude Code, status asks for a re-apply" /bin/bash "$I" --status
/bin/bash "$I" --apply >/dev/null
eq "re-apply after the update adds onFailure" "$(jq -r '[.hooks.PreToolUse[].hooks[] | select(.command|endswith("lane-guard.sh")) | .onFailure] | first' "$CH/settings.json")" block
ok "destructive git commands ask" jq -e '.permissions.ask | index("Bash(git reset --hard*)")' "$CH/settings.json"
ok "auto-mode deny rules keep the built-in ones" jq -e '.autoMode.hard_deny[0] == "$defaults"' "$CH/settings.json"
/bin/bash "$I" --rollback >/dev/null; /bin/bash "$I" --rollback >/dev/null
rc 1 "status on a home with nothing installed says so" /bin/bash "$I" --status
ok "…in plain words" grep -q "NOT INSTALLED" <<<"$(/bin/bash "$I" --status)"
# Run as `bash install.sh` from the repo folder ($0 has no slash): apply must still finish with its status check.
(cd "$ROOT" && /bin/bash install.sh --apply >"$TMP/rel.out" 2>&1); eq "relative invocation exits 0" "$?" 0
ok "relative invocation ran the status check" grep -q "STATUS OK" "$TMP/rel.out"
/bin/bash "$I" --rollback >/dev/null
finish
