#!/bin/sh
# Runs every test in the suite and prints one line per test plus a total:
#   the regression suite (fem_regress), each self-checking test program, and -- if node is
#   installed -- the viewer's tests. Exit status is 0 only if everything passed and nothing
#   that should have been built is missing.
#
#   ./test_all.sh          programs are looked for in ./bin   (override: BIN=dir ./test_all.sh)
#   -v                     show each test's full output, not just failures
BIN="${BIN:-bin}"
VERBOSE=0
[ "$1" = "-v" ] && VERBOSE=1
PASS=0; FAIL=0; MISSING=0
TMP="${TMPDIR:-/tmp}/femtest.$$"

run() {  # run <label> <command...>
  label="$1"; shift
  if "$@" >"$TMP" 2>&1; then
    PASS=$((PASS + 1)); printf '  PASS     %s   (%s)\n' "$label" "$(tail -n 1 "$TMP" | tr -d '\r')"
    [ $VERBOSE = 1 ] && cat "$TMP"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL     %s\n' "$label"; cat "$TMP"
  fi
}
need() {  # need <exe> -> 0 if present, else count it as missing
  if [ -x "$BIN/$1" ]; then return 0; fi
  MISSING=$((MISSING + 1)); printf '  MISSING  %s   (not built: expected %s/%s)\n' "$1" "$BIN" "$1"; return 1
}

echo "Regression suite"
if need fem_regress; then run "fem_regress tests/regression" "$BIN/fem_regress" tests/regression --bin "$BIN"; fi

echo "Self-checking test programs"
for t in matrix_test results_test shell_results_test skyline_test fingerprint_test \
         run_patch_test run_q8_membrane_test run_q8_plate_test run_q8_shell_test run_q8_shell3d_test \
         run_growthlaw_test; do
  if need "$t"; then run "$t" "$BIN/$t"; fi
done

if command -v node >/dev/null 2>&1 && [ -f viewer/test/run_tests.js ]; then
  echo "Viewer (node)"
  run "viewer/test/run_tests.js" node viewer/test/run_tests.js
else
  echo "Viewer tests skipped (node not installed)"
fi

rm -f "$TMP"
echo
echo "$PASS passed, $FAIL failed, $MISSING missing"
[ $FAIL -eq 0 ] && [ $MISSING -eq 0 ]
