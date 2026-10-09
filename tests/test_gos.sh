#!/bin/bash
# Bound gos (change 4): a go must unlock exactly one matching run and nothing else.
. "$(dirname "$0")/lib.sh"
export OPSLIB="$ROOT/claude/lib/opslib.sh" GO_DIR="$TMP/gos"
. "$OPSLIB"
cat > "$TMP/job.sh" <<'EOF'
#!/bin/bash
. "$OPSLIB"
GO_ENV="EXPECT_N" GO_FILES="$(dirname "$0")/helper.py"
require_go "$@" || exit 4
echo RAN
EOF
echo "print(1)" > "$TMP/helper.py"
run() { (cd "$TMP" && GO_REQUIRED=1 GO_SCRIPT="$TMP/job.sh" EXPECT_N=${N:-5} /bin/bash "$TMP/job.sh" "$@"); }
grant() { (cd "$TMP" && EXPECT_N=${N:-5} /bin/bash "$ROOT/bin/go.sh" "$TMP/job.sh" --env EXPECT_N --files "$TMP/helper.py" -- "$@") >/dev/null; }

rc 0 "flag off: require_go is a no-op" env OPSLIB="$OPSLIB" /bin/bash "$TMP/job.sh" a
rc 4 "flag on, no go: refused" run a
grant a
rc 0 "matching go: runs" run a
rc 4 "go is consumed after one run" run a
grant a
rc 4 "different args: refused" run b
N=6 rc 4 "different EXPECT env value: refused" run a
echo "print(2)" > "$TMP/helper.py"
rc 4 "changed helper source: refused" run a
echo "print(1)" > "$TMP/helper.py"
echo "# edited" >> "$TMP/job.sh"
rc 4 "changed script bytes: refused" run a
perl -i -ne 'print unless eof' "$TMP/job.sh"   # drop the last line (portable; no BSD sed -i '')
rc 0 "restored script: the go still matches" run a
grant a; f=$(ls "$GO_DIR"/*.go | head -1); perl -i -pe 's/^expires_epoch=.*/expires_epoch=1/' "$f"
rc 4 "expired go: refused" run a
finish
