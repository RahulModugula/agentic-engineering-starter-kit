#!/bin/bash
# Run every tests/test_*.sh, up to JOBS at a time (default: CPU count); exit non-zero if any file fails.
# Each file's output is captured to its own file and printed in sorted order, so the log reads like a serial run.
# bash 3.2 compatible (macOS /bin/bash): the parallelism comes from xargs -P, not `wait -n`.
cd "$(dirname "$0")" || exit 2
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)}
case "$JOBS" in ''|*[!0-9]*|0) JOBS=4;; esac
OUT=$(mktemp -d "${TMPDIR:-/tmp}/engrun.XXXXXX") || exit 2
trap 'rm -rf "$OUT"' EXIT
# The worker always exits 0 (xargs aborts on a 255); each file's real status is written to <file>.rc.
for t in test_*.sh; do printf '%s\n' "$t"; done | xargs -n 1 -P "$JOBS" /bin/bash -c \
  't=$1; TEST_FILE=$t /bin/bash "$t" >"$0/$t.out" 2>&1; echo $? >"$0/$t.rc"; exit 0' "$OUT"
fail=0
for t in test_*.sh; do
  cat "$OUT/$t.out" 2>/dev/null
  rc=$(cat "$OUT/$t.rc" 2>/dev/null)
  if [ "$rc" != 0 ]; then
    fail=1
    [ -z "$rc" ] && echo "  FAIL [$t] did not run (no exit status recorded)"
  fi
done
[ $fail = 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
