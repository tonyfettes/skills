#!/bin/bash
# verify.sh <workdir> — exit 0 = pass, non-zero = fail.
#
# Design-graded task: the prompt never says what a failing repo should
# produce; the pass bar is that the signature models absence/failure
# (String? or raise) instead of returning a bare String ("" sentinel).
# Behavioral conformance is injected to match whichever shape was chosen.
set -u
WORK="$1"
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "VERIFY_FAIL: $*"; exit 1; }

cd "$WORK" || fail "workdir missing"

# Fixed harness: agents must not weaken the test double.
cp "$TASK_DIR/template/vcs/proc.mbt" vcs/proc.mbt || fail "cannot restore proc.mbt"

moon check >/dev/null 2>&1 || { moon check 2>&1 | tail -20; fail "moon check failed"; }
moon info >/dev/null 2>&1 || fail "moon info failed"
MBTI="vcs/pkg.generated.mbti"
[ -f "$MBTI" ] || fail "missing $MBTI"
SIG="$(grep 'current_branch' "$MBTI")"
[ -n "$SIG" ] || fail "no public current_branch in $MBTI"
echo "signature: $SIG"

rm -rf conformance
if printf '%s' "$SIG" | grep -q 'String?'; then
  cp -R "$TASK_DIR/conformance-option" conformance || fail "cannot inject conformance"
elif printf '%s' "$SIG" | grep -q 'raise'; then
  cp -R "$TASK_DIR/conformance-raise" conformance || fail "cannot inject conformance"
elif printf '%s' "$SIG" | grep -qE '\?$'; then
  # Option-shaped custom return (e.g. -> EditorCommand?): absence is modeled
  # in the type, which is the point under test; generic behavioral
  # conformance cannot compile against an agent-chosen payload type.
  echo "option-shaped custom return; behavioral conformance skipped"
  echo "VERIFY_PASS"
  exit 0
else
  fail "current_branch does not model the missing value idiomatically — expected String? or raise (a bare String hides a repo without a branch in a sentinel; Result is not idiomatic MoonBit error handling). got: $SIG"
fi

moon check >/dev/null 2>&1 \
  || { moon check 2>&1 | tail -20; fail "moon check failed after conformance injection"; }
moon test -p eval/vcs/conformance 2>&1 | tail -10
moon test -p eval/vcs/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

echo "VERIFY_PASS"
