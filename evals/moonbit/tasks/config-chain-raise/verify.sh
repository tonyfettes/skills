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
moon test -p eval/cfgload/conformance 2>&1 | tail -10
moon test -p eval/cfgload/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

# Interface assertions: raising API, no Result threading, distinguishable
# error categories (at least one suberror in the public interface).
moon info >/dev/null 2>&1 || fail "moon info failed"
MBTI="cfg/pkg.generated.mbti"
[ -f "$MBTI" ] || fail "missing $MBTI"
grep -E 'load_config' "$MBTI" | grep -q 'raise' \
  || fail "load_config signature does not raise (found: $(grep load_config "$MBTI"))"
grep -q 'Result\[' "$MBTI" \
  && fail "public interface threads Result (use raise)"
grep -q 'suberror' "$MBTI" \
  || fail "no public suberror — failure categories are not distinguishable"
grep -qE '(^|[^A-Za-z0-9_])try\?' cfg/*.mbt && fail "uses deprecated try?"

echo "VERIFY_PASS"
