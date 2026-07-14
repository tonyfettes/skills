#!/bin/bash
# verify.sh <workdir> — exit 0 = pass, non-zero = fail.
set -u
WORK="$1"
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "VERIFY_FAIL: $*"; exit 1; }

cd "$WORK" || fail "workdir missing"

rm -rf conformance
cp -R "$TASK_DIR/conformance" conformance || fail "cannot inject conformance"

moon check >/dev/null 2>&1 || { moon check 2>&1 | tail -20; fail "moon check failed"; }
moon test -p eval/eventlog/conformance 2>&1 | tail -10
moon test -p eval/eventlog/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

# Mid-pipeline Option flattening is the anti-pattern under test; nothing in
# this task legitimately needs an empty-string fallback.
if grep -n 'unwrap_or("")' events/*.mbt; then
  fail "flattens an absent field into an empty-string sentinel"
fi

echo "VERIFY_PASS"
