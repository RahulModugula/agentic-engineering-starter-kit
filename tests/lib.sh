# Minimal test helpers (bash 3.2). Each test file sources this, calls ok/no/eq, and ends with `finish`.
PASS=0; FAIL=0; TEST_FILE=${TEST_FILE:-$(basename "$0")}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/engtest.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export KIT_TOOLS=${KIT_TOOLS-none}   # install.sh otherwise sets up every agent CLI on this machine's PATH
_res() { if [ "$1" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL [$TEST_FILE] $2"; fi; }
ok() { local d=$1; shift; "$@" >/dev/null 2>&1; _res $? "$d (expected success)"; }          # command must succeed
no() { local d=$1; shift; "$@" >/dev/null 2>&1 && _res 1 "$d (expected failure)" || _res 0 "$d"; }  # must fail
rc() { local want=$1 d=$2; shift 2; "$@" >/dev/null 2>&1; local got=$?; [ "$got" = "$want" ]; _res $? "$d (rc want $want got $got)"; }
eq() { [ "$2" = "$3" ]; _res $? "$1 (want [$3] got [$2])"; }
finish() { echo "$TEST_FILE: $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]; }
