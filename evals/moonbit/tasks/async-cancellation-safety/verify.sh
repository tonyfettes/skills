#!/bin/bash
# verify.sh <workdir> — exit 0 = pass, non-zero = fail.
set -u
WORK="$1"
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "VERIFY_FAIL: $*"; exit 1; }

cd "$WORK" || fail "workdir missing"

# Anti-cheat: restore the fixed test double before grading.
cp "$TASK_DIR/template/session/conn.mbt" session/conn.mbt || fail "cannot restore conn.mbt"

rm -rf conformance
cp -R "$TASK_DIR/conformance" conformance || fail "cannot inject conformance"

moon check --target native >/dev/null 2>&1 \
  || { moon check --target native 2>&1 | tail -20; fail "moon check failed"; }
moon test --target native -p eval/cancelsafe/conformance 2>&1 | tail -20
moon test --target native -p eval/cancelsafe/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

echo "VERIFY_PASS"
