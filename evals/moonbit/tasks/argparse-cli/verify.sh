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
moon test -p eval/mgrep/conformance 2>&1 | tail -10
moon test -p eval/mgrep/conformance >/dev/null 2>&1 \
  || fail "conformance tests failed"

# Static: CLI parsing must use the stdlib @argparse, not a hand-rolled loop
# (skill: @argparse is the first choice for CLI argument parsing).
grep -rq 'core/argparse' cli/moon.pkg* 2>/dev/null \
  || fail "cli package does not import moonbitlang/core/argparse"

echo "VERIFY_PASS"
