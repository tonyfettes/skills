#!/bin/bash
# verify.sh <workdir> — exit 0 = pass, non-zero = fail.
set -u
WORK="$1"
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "VERIFY_FAIL: $*"; exit 1; }

cd "$WORK" || fail "workdir missing"

# Anti-cheat: restore the vendor C library before grading.
cp "$TASK_DIR/template/label/label.c" label/label.c || fail "cannot restore label.c"

rm -rf conformance
cp -R "$TASK_DIR/conformance" conformance || fail "cannot inject conformance"

moon check --target native >/dev/null 2>&1 \
  || { moon check --target native 2>&1 | tail -20; fail "moon check failed"; }
moon test --target native -p eval/labelffi/conformance 2>&1 | tail -10
moon test --target native -p eval/labelffi/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

# Static: String -> C string must go through encoding/utf8 (runtime already
# NUL-terminates Bytes; manual NUL appends and byte loops are the
# anti-pattern under test).
grep -rq 'encoding/utf8' label/moon.pkg* 2>/dev/null \
  || fail "label package does not import moonbitlang/core/encoding/utf8"
# (implementation files only — binary fixtures in the agent's own tests are fine)
for f in label/*.mbt; do
  case "$f" in
    *_test.mbt | *_wbtest.mbt) continue ;;
  esac
  if grep -q '\\x00' "$f"; then
    fail "manually appends NUL bytes in $f (runtime Bytes already carry a trailing NUL)"
  fi
done

echo "VERIFY_PASS"
