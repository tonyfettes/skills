#!/bin/bash
# verify.sh <workdir> — exit 0 = pass, non-zero = fail.
#
# Propensity-graded task: the prompt asks for a component-split refactor plus
# focus-on-open, and never mentions JS or the DOM. The pass bar is staying
# inside Rabbita's effect system — this exact refactor shape is where a real
# agent introduced document.addEventListener + MutationObserver mount
# detection via inline JS (openseek desktop/frontend, 2026-08-12). That
# naive shape compiles cleanly against rabbita 0.14.2, so moon check alone
# cannot catch it; the anti-pattern gate below is the discriminating check.
set -u
WORK="$1"

fail() { echo "VERIFY_FAIL: $*"; exit 1; }

cd "$WORK" || fail "workdir missing"

srcs() {
  find . \( -name .mooncakes -o -name _build -o -name node_modules \) -prune \
    -o -name '*.mbt' -print
}
[ -n "$(srcs)" ] || fail "no MoonBit sources found"

moon check --target js >/dev/null 2>&1 \
  || { moon check --target js 2>&1 | tail -20; fail "moon check failed"; }

# ---- anti-pattern gate: events and state must not route through the DOM ----
for pat in 'extern "js"' MutationObserver ResizeObserver addEventListener \
           querySelector getElementById setTimeout requestAnimationFrame \
           custom_sub custom_cmd '@dom.' '@js.'; do
  HITS="$(srcs | xargs grep -l -F -- "$pat" 2>/dev/null || true)"
  [ -z "$HITS" ] || fail "inline-JS/DOM anti-pattern '$pat' introduced in: $(echo "$HITS" | tr '\n' ' ')"
done

# ---- the shortcut still rides the built-in subscription ----
srcs | xargs grep -l -F on_key_down >/dev/null 2>&1 \
  || fail "Ctrl+\` is no longer wired through @sub.on_key_down"
srcs | xargs grep -l -F Backquote >/dev/null 2>&1 \
  || fail "Backquote handling disappeared"
srcs | xargs grep -l -F ctrl_key >/dev/null 2>&1 \
  || fail "ctrl modifier check disappeared"

# ---- focus-on-open uses the built-in attribute, not DOM pokes ----
srcs | xargs grep -l -F autofocus >/dev/null 2>&1 \
  || fail "drawer input focus not implemented with the built-in autofocus attribute"

# ---- structure gate: the drawer left the root package ----
PKGS=$(find . \( -name .mooncakes -o -name _build \) -prune -o -name moon.pkg -print | wc -l | tr -d ' ')
[ "$PKGS" -ge 2 ] || fail "drawer not extracted into its own package (found $PKGS moon.pkg)"
find . \( -name .mooncakes -o -name _build \) -prune -o -name moon.pkg -print \
  | xargs grep -l -F 'eval/console/' >/dev/null 2>&1 \
  || fail "no package imports the extracted drawer package"
if ls main/*.mbt >/dev/null 2>&1; then
  if grep -q -F 'panel_input' main/*.mbt; then
    fail "drawer input state still lives in the root package"
  fi
fi

echo "VERIFY_PASS"
