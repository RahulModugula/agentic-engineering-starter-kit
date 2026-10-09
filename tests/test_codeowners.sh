#!/bin/bash
# review-codeowners.py: default-deny ordering, human paths last, rules owned by humans, bad owners refused.
. "$(dirname "$0")/lib.sh"
printf 'default human\nagent web/**\nagent tests/**\nhuman src/auth/**\nescalate import.*db\n' > "$TMP/p"
out=$(python3 "$ROOT/bin/review-codeowners.py" @alice @org/core --policy "$TMP/p")
eq "first rule: everything needs a human" "$(sed -n 2p <<<"$out")" "* @alice @org/core"
ok "agent paths are ownerless" grep -qx "web/\*\*" <<<"$out"
eq "human path comes AFTER the agent paths" "$(grep -n 'src/auth' <<<"$out" | cut -d: -f1)" "5"
ok "policy file always human" grep -qx "/.review-tiers @alice @org/core" <<<"$out"
ok "workflows always human" grep -qx "/.github/ @alice @org/core" <<<"$out"
rc 1 "owners without @ are refused" python3 "$ROOT/bin/review-codeowners.py" alice --policy "$TMP/p"
finish
