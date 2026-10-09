#!/bin/bash
# install.sh in a sandbox: dry run changes nothing; apply links + backs up; rollback restores byte-for-byte;
# status detects drift; unmanaged state is never touched.
. "$(dirname "$0")/lib.sh"
CH=$TMP/home/.claude; export CLAUDE_HOME=$CH INSTALL_BACKUPS=$TMP/home/.claude-backups MERGE_STATE=$TMP/ms
mkdir -p "$CH/hooks/.state" "$CH/projects/p" "$CH/roles"
echo "old settings" > "$CH/settings.json"
echo "old lane role" > "$CH/roles/lane.md"
echo "session state" > "$CH/hooks/.state/verify-x"
echo "transcript" > "$CH/projects/p/t.jsonl"
(cd "$CH" && find . -type f | sort | xargs shasum) > "$TMP/before.sha"
I="$ROOT/install.sh"
mkdir -p "$TMP/fb"; printf '#!/bin/bash\necho "${FAKE_CLAUDE_VER:-2.1.295} (Claude Code)"\n' > "$TMP/fb/claude"; chmod +x "$TMP/fb/claude"
export PATH="$TMP/fb:$PATH"
FAKE_CLAUDE_VER=2.1.280 rc 1 "apply refuses on Claude Code < 2.1.290" /bin/bash "$I" --apply
no "the refused apply changed nothing" test -L "$CH/settings.json"

out=$(/bin/bash "$I")
ok "dry run lists a changed file" grep -q "~ DIFF  settings.json" <<<"$out"
ok "dry run lists a new file" grep -q "+ NEW   lib/opslib.sh" <<<"$out"
(cd "$CH" && find . -type f | sort | xargs shasum) > "$TMP/after-dry.sha"
ok "dry run changed nothing" cmp -s "$TMP/before.sha" "$TMP/after-dry.sha"

/bin/bash "$I" --apply >/dev/null
ok "apply links settings.json into the repo" test "$(readlink "$CH/settings.json")" = "$ROOT/claude/settings.json"
ok "apply links a hook" test -L "$CH/hooks/notify.sh"
ok "apply leaves hooks/.state alone" grep -q "session state" "$CH/hooks/.state/verify-x"
ok "apply leaves projects/ alone" test -f "$CH/projects/p/t.jsonl" -a ! -L "$CH/projects/p/t.jsonl"
ok "status OK after apply" /bin/bash "$I" --status
ok "dry run after apply: nothing to change" grep -q "^0 path(s) would change" <<<"$(/bin/bash "$I")"

rm "$CH/settings.json"; echo "rewritten by a tool" > "$CH/settings.json"
no "status detects a symlink replaced by a plain file" /bin/bash "$I" --status

/bin/bash "$I" --rollback >/dev/null
(cd "$CH" && find . -type f | sort | xargs shasum) > "$TMP/after-rb.sha"
ok "rollback restores every original file byte-for-byte" cmp -s "$TMP/before.sha" "$TMP/after-rb.sha"
no "rollback removes files that didn't exist before" test -e "$CH/lib/opslib.sh"
ok "rollback leaves no stray symlinks" test -z "$(find "$CH" -type l)"

# Review finding: apply twice, roll back twice -> the ORIGINAL files come back (not links, not nothing).
# Both applies "in the same second" (a fake date): backups must still sort in the order they were made.
mkdir -p "$TMP/samesec"; printf '#!/bin/bash\necho 20300101-000000\n' > "$TMP/samesec/date"; chmod +x "$TMP/samesec/date"
PATH="$TMP/samesec:$PATH" /bin/bash "$I" --apply >/dev/null; PATH="$TMP/samesec:$PATH" /bin/bash "$I" --apply >/dev/null
/bin/bash "$I" --rollback >/dev/null
ok "first rollback undoes only the second apply: links stay" test -L "$CH/settings.json"
/bin/bash "$I" --rollback >/dev/null
(cd "$CH" && find . -type f | sort | xargs shasum) > "$TMP/after-rb2.sha"
ok "apply x2 + rollback x2 restores the originals" cmp -s "$TMP/before.sha" "$TMP/after-rb2.sha"
ok "no symlinks left after the double rollback" test -z "$(find "$CH" -type l)"
rc 1 "a third rollback finds no unused backup" /bin/bash "$I" --rollback

# merge-queue migration: copies the old inline list, leaves the old script alone
mkdir -p "$TMP/old"; printf 'x\nwhile read R P H N; do :; done <<LIST\n# o/r 1 a\no/r 2 b\nLIST\n' > "$TMP/old/merge_next.sh"
echo "o/r 2 b" > "$TMP/old/verified.txt"; cp "$TMP/old/merge_next.sh" "$TMP/old.copy"
OLD_MERGE_DIR=$TMP/old /bin/bash "$I" --apply >/dev/null
eq "queue migrated (commented line kept as comment)" "$(cat "$TMP/ms/queue.txt")" "$(printf '# o/r 1 a\no/r 2 b')"
ok "verified.txt copied" cmp -s "$TMP/old/verified.txt" "$TMP/ms/verified.txt"
ok "old merge script untouched" cmp -s "$TMP/old/merge_next.sh" "$TMP/old.copy"
/bin/bash "$I" --rollback >/dev/null
rc 2 "unknown flag prints usage" /bin/bash "$I" --bogus
finish
