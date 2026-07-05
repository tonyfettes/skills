#!/bin/bash
# verify.sh <workdir> — exit 0 = pass, non-zero = fail.
# Grades the agent's solution: behavioral conformance tests + static checks.
set -u
WORK="$1"
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "VERIFY_FAIL: $*"; exit 1; }

cd "$WORK" || fail "workdir missing"

# Inject hidden conformance package (agent never sees or edits it).
rm -rf conformance
cp -R "$TASK_DIR/conformance" conformance || fail "cannot inject conformance"

moon check >/dev/null 2>&1 || { moon check 2>&1 | tail -20; fail "moon check failed"; }
moon test -p eval/wirecodec/conformance 2>&1 | tail -20
moon test -p eval/wirecodec/conformance >/dev/null 2>&1 || fail "conformance tests failed"

# Static: String<->Bytes must go through moonbitlang/core/encoding/utf8
# (skill: never hand-roll UTF-8 conversion; String::to_bytes() is UTF-16LE).
grep -rq 'encoding/utf8' wire/moon.pkg* 2>/dev/null \
  || fail "wire package does not import moonbitlang/core/encoding/utf8"

echo "VERIFY_PASS"
