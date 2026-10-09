#!/bin/bash
# Run every tests/test_*.sh; exit non-zero if any file fails.
cd "$(dirname "$0")" || exit 2
fail=0
for t in test_*.sh; do TEST_FILE=$t /bin/bash "$t" || fail=1; done
[ $fail = 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
