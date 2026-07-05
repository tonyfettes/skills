#!/bin/bash
# verify.sh <workdir> — exit 0 = pass, non-zero = fail.
set -u
WORK="$1"
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "VERIFY_FAIL: $*"; exit 1; }

cd "$WORK" || fail "workdir missing"

rm -rf conformance
cp -R "$TASK_DIR/conformance" conformance || fail "cannot inject conformance"

moon check --target native >/dev/null 2>&1 \
  || { moon check --target native 2>&1 | tail -20; fail "moon check failed"; }
moon test --target native -p eval/blobstore/conformance 2>&1 | tail -20
moon test --target native -p eval/blobstore/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

# Static: async programs must do fs IO through moonbitlang/async/fs,
# not the sync moonbitlang/x/fs (blocks the event loop).
if grep -rq 'moonbitlang/x/fs' moon.mod moon.mod.json store/moon.pkg* 2>/dev/null; then
  fail "uses moonbitlang/x/fs (sync IO) inside an async program"
fi
grep -rq 'moonbitlang/async/fs' store/moon.pkg* 2>/dev/null \
  || fail "store package does not import moonbitlang/async/fs"

echo "VERIFY_PASS"
