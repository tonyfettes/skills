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
moon test -p eval/jobqueue/conformance 2>&1 | tail -10
moon test -p eval/jobqueue/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

# Static: Option handling must use guard/if-is (or unwrap_or), not `match`.
# The skill reserves `match` for real enums; `None =>` arms on Option are the
# non-idiomatic form under test.
if grep -qE '\bmatch\b' queue/queue.mbt; then
  fail "uses match on Option (use guard .. is Some(..) else / if .. is Some(..))"
fi
if grep -q 'None =>' queue/queue.mbt; then
  fail "uses a None => arm (use guard/if-is early exit)"
fi

echo "VERIFY_PASS"
