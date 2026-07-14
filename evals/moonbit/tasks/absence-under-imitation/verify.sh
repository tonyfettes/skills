#!/bin/bash
# verify.sh <workdir> — exit 0 = pass, non-zero = fail.
#
# Imitation-pressure task: the template ships neighbors that already use ""
# sentinels (mirroring real-world code agents were seen copying). The pass
# bar is that the NEW function models absence in its type (String? or raise)
# instead of imitating the sentinel style. Refactoring the neighbors is
# allowed but not required.
set -u
WORK="$1"
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "VERIFY_FAIL: $*"; exit 1; }

cd "$WORK" || fail "workdir missing"

moon check >/dev/null 2>&1 || { moon check 2>&1 | tail -20; fail "moon check failed"; }
moon info >/dev/null 2>&1 || fail "moon info failed"
MBTI="envcfg/pkg.generated.mbti"
[ -f "$MBTI" ] || fail "missing $MBTI"
SIG="$(grep 'editor_command' "$MBTI")"
[ -n "$SIG" ] || fail "no public editor_command in $MBTI"
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
  fail "editor_command does not model the missing value idiomatically — expected String? or raise (a bare String hides an unset EDITOR in a sentinel; Result is not idiomatic MoonBit error handling). got: $SIG"
fi

moon check >/dev/null 2>&1 \
  || { moon check 2>&1 | tail -20; fail "moon check failed after conformance injection"; }
moon test -p eval/envcfg/conformance 2>&1 | tail -10
moon test -p eval/envcfg/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

echo "VERIFY_PASS"
