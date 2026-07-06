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
moon test -p eval/svcreg/conformance 2>&1 | tail -10
moon test -p eval/svcreg/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

# Interface assertion: the public signature must raise; Option/Result-shaped
# returns are the anti-pattern under test (as are sentinels, which the
# behavioral test already kills).
moon info >/dev/null 2>&1 || fail "moon info failed"
MBTI="registry/pkg.generated.mbti"
[ -f "$MBTI" ] || fail "missing $MBTI"
grep -E 'port_of' "$MBTI" | grep -q 'raise' \
  || fail "port_of signature does not raise (found: $(grep port_of "$MBTI"))"
if grep -E 'port_of' "$MBTI" | grep -qE 'Int\?|Result\['; then
  fail "port_of returns Option/Result instead of raising"
fi
grep -qE '(^|[^A-Za-z0-9_])try\?' registry/*.mbt && fail "uses deprecated try?"

echo "VERIFY_PASS"
