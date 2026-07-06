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
moon test -p eval/ledger/conformance 2>&1 | tail -10
moon test -p eval/ledger/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

# Interface assertion: Account must be ABSTRACT outside the package
# (`type Account` in the .mbti). `pub`/`pub(all)` struct exposes fields —
# with a mut balance field, pub(all) lets any dependent package break the
# invariant, which behavioral tests inside this module cannot observe.
moon info >/dev/null 2>&1 || fail "moon info failed"
MBTI="account/pkg.generated.mbti"
[ -f "$MBTI" ] || fail "missing $MBTI"
grep -qE '^type Account' "$MBTI" \
  || fail "Account is not abstract in the public interface: $(grep -E 'Account( |$|\{)' "$MBTI" | head -1)"
grep -qE 'struct Account' "$MBTI" \
  && fail "Account struct layout is exposed: $(grep 'struct Account' "$MBTI")"

echo "VERIFY_PASS"
