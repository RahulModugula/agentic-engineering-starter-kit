#!/bin/bash
# bin/ratchet.py: a baseline that only shrinks. Each rule is checked from both sides (it fires; look-alikes pass).
. "$(dirname "$0")/lib.sh"
R="python3 $ROOT/bin/ratchet.py"
cd "$TMP" || exit 1
echo '{"a.py": 3, "b.py": 2}' > base.json

echo '{"a.py": 3, "b.py": 2}' > same.json
rc 0 "equal counts pass" $R check base.json same.json

echo '{"a.py": 1}' > down.json
rc 0 "a lower count and a vanished key pass" $R check base.json down.json

echo '{"a.py": 4, "b.py": 2}' > up.json
rc 1 "a raised count fails" $R check base.json up.json
rc 0 "a raised count with --report-only exits 0" $R check base.json up.json --report-only
eq "report-only still prints the rise" "$($R check base.json up.json --report-only | grep -c 'UP a.py: 3 -> 4')" "1"

echo '{"a.py": 3, "c.py": 1}' > new.json
rc 1 "a new key with a count above 0 fails" $R check base.json new.json
echo '{"a.py": 3, "c.py": 0}' > newzero.json
rc 0 "a new key at 0 passes" $R check base.json newzero.json

echo '{"a.py": "3"}' > str.json
rc 2 "a string count is bad input" $R check base.json str.json
echo '{"a.py": -1}' > neg.json
rc 2 "a negative count is bad input" $R check base.json neg.json
echo '{"a.py": true}' > bool.json
rc 2 "a boolean count is bad input" $R check base.json bool.json
echo '[1]' > list.json
rc 2 "a non-object file is bad input" $R check base.json list.json
rc 2 "a missing file is bad input" $R check base.json nope.json
rc 2 "an unknown command is a usage error" $R frob base.json same.json
rc 2 "--report-only is only for check" $R shrink base.json same.json --report-only

cp base.json shrink.json
echo '{"a.py": 1, "b.py": 0}' > cur.json
rc 0 "shrink accepts lower counts" $R shrink shrink.json cur.json
eq "shrink writes the new baseline and drops zeros" "$(python3 -c 'import json;print(json.load(open("shrink.json")))')" "{'a.py': 1}"

cp base.json keep.json
rc 1 "shrink refuses while a count is up" $R shrink keep.json up.json
eq "a refused shrink leaves the baseline untouched" "$(cmp -s keep.json base.json && echo same)" "same"
finish
