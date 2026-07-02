# Optimizing MoonBit hot paths (native backend)

For data-layout work (`#valtype`, unboxing, flat arrays) read `valtype.md`
first. This file is about the *code* side: refcount traffic, hidden
polymorphic dispatch, and cross-package inlining on the native backend.

One design rule that precedes any measurement: **a `mut` field forces heap
allocation of an otherwise value-shaped struct**. For hot small-state types
(decoders, cursors, counters), prefer an immutable value newtype with a
functional-update shape — `struct Decoder(Int)` with
`Decoder::push(self, byte : Byte) -> (Decoder, DecodeStep)` — over
`struct Decoder { mut state : Int }`.

## Golden rule: read the generated C, then the assembly

Do not guess what the compiler does. Source-level intuitions ("this is a
branch", "this allocates", "this is branchless") are frequently wrong after
two lowering stages (moonc → C → clang/gcc). The workflow:

1. Build a TU that contains the function. A library package only emits
   `.core` IR; readable C is generated when linking an executable or a
   **whitebox test** (white-box tests link the whole package in):
   ```sh
   moon test -p <pkg> --target native --release --build-only
   # → _build/native/release/test/<module>/<pkg>/<pkg>.whitebox_test.c
   ```
   A benchmark/main build emits C under
   `_build/native/release/build/<...>/<name>.c` — prefer this when you want
   the *same* inlining decisions the profiled binary used (whitebox and
   bench builds inline differently).
2. Find the function. Symbols are mangled
   `_M0MP<len><module><len><pkg><len><Type><len><method>`; the **definition**
   is the `^int32_t _M0MP...name(` line (earlier matches are forward
   declarations / call sites). Take the last match.
3. For the machine-code truth, compile that one C TU to assembly:
   ```sh
   clang -O2 -I"$(dirname "$(find ~/Library/MoonBit ~/.moon -name moonbit.h | head -1)")" \
     -S -o /tmp/f.s <that>.c
   ```
   Then read the `_<symbol>:` block.

## Profile first; the bottleneck is usually not what you're staring at

Never assert that a change is faster or slower without a benchmark or profile
run — propose the measurement first, then conclude. This applies to review
comments and design discussions, not just committed optimizations.

```sh
moon run ./bench/<name> --release --target native --profile
```
Read **"Top self time"** and especially **"Runtime leaf costs attributed to
MoonBit callers"** — the latter pins `moonbit_incref/decref_inlined` samples
onto the MoonBit function whose machine code contains them (incref/decref
inline into the caller, so a `callee <- moonbit_decref_inlined` line means
the cost lives in `callee`'s body, often from a *different* source function
that clang inlined into it).

Profiling is noisy at a few hundred 1 ms samples. For an honest before/after,
`git stash` the change, rebuild, run the bench **3–4×**, then pop and run
3–4× again, comparing means. A single baseline run will mislead you.

## Pitfall 1 — refcount traffic on the per-element hot path

ARC (incref/decref) was the single biggest cost in a terminal print path
(~21% of self time), an order above any arithmetic. Two recurring causes,
both fixable from source with no API change:

**(a) A heap value held live across a call between an indexed load and its
store.** This pattern:
```moonbit
self.cells[r][c] = make(..., self.table.intern(x), ...)  // intern between load & store
```
forces the compiler to `incref` the row array (and conservatively the table)
to keep them alive across `intern`, then `decref` after — per element. Fix by
computing everything into locals first so the store has **no intervening
call**:
```moonbit
let id = self.table.intern(x)
let v = make(..., id, ...)
self.cells[r][c] = v   // load → store, nothing between → no incref/decref
```
This removed all 6 per-cell refcount ops in one case (the row-array *and* the
table increfs both vanished once the liveness window closed).

**(b) Calling a method that only fast-returns for the common argument.**
`table.intern(None)` that immediately returns a sentinel still costs a call +
an incref/decref of the table receiver. Guard the common case out:
```moonbit
let id = if x is Some(_) { self.table.intern(x) } else { sentinel_id }
```

Always confirm in the C that the `moonbit_incref`/`moonbit_decref` lines are
gone for the common path.

## Pitfall 2 — `!=` / `==` on a derived-`Eq` enum becomes a polymorphic call

For a simple (payload-free) enum with `derive(Eq)`, this on a hot path:
```moonbit
if x.kind() != SomeVariant { ... }
```
does **not** compile to an integer tag compare. `!=` resolves to the generic
`Eq::not_equal` **default-impl**, emitted as an out-of-line, polymorphic call
(`_M0IP..._24default__implPB2Eq10not__equal...`); `==` resolves to the derived
`Eq::equal`, still an out-of-line call. Both run per element.

Fix: compare with **pattern matching**, which lowers to a tag test (`switch`):
- guard form: `guard x.kind() is SomeVariant else { return }`
- negation: `if !(x.kind() is SomeVariant) { ... }`
- when a following `match` already dispatches on the value, fold the
  comparison into the arms instead of testing first:
  ```moonbit
  // was: if a != b { match a { Wide => .., SpacerTail => .., _ => () } }
  match a {
    Wide => if !(b is Wide) { ... }
    SpacerTail => if !(b is SpacerTail) { ... }
    _ => ()   // arms that were no-ops never needed the != guard
  }
  ```
Verify the `default__impl...Eq...not_equal` / `...Eq...equal` call is gone and
replaced by a `switch`.

## Pitfall 3 — small accessors don't inline across packages

The native inliner is conservative across package boundaries. It **will**
inline a leaf that is a single expression (e.g. `has_grapheme = (self.0 >>
S) & M != 0` folds into a bit test at the call site), but **stops** when the
callee is multi-level or returns a constructed value:
- `self.flags().wide()` (two-level, builds an intermediate struct) → not
  inlined. Rewriting it to decode the field directly in one `match` removes
  the intermediate but a value-returning `match` (enum result) still may not
  inline — returning `Bool` from a single comparison inlines, returning an
  enum often does not.
- A builder like `with_bit(mask, value)` carrying a set/clear/noop branch is
  too big; a branchless single-expression setter (`self.0 | MASK`) folds in.
  When you only ever set or only ever clear on the hot path, add dedicated
  `set_x` / `clear_x` (each one expression) instead of the general `with_x`.

So: make hot leaves single, branchless expressions. Don't fight the inliner
on value-returning matches — instead avoid the call (see Pitfall 4).

## Pitfall 4 — split functions re-derive and re-check what a sibling knows

When a per-element operation is spread across functions (e.g. `read old →
write → update flags`), each non-inlined function independently re-loads the
container, re-checks bounds, and recomputes values a sibling already had. In
one case the cell slot was bounds-checked and dereferenced **three times**
per element, and the flag-update re-read the word just written to recompute
bits that the writer already knew (`has_grapheme` always false on that path,
`has_styled = style_id != default`, `has_hyperlink = has_link`).

Fix by **fusing** the hot path into one private function that loads the
container once and threads the known values instead of re-reading. Keep the
original standalone functions for their other callers (don't change a `pub`
signature with many call sites; add a private fused variant). This removed a
full re-read + recompute per element (~7% end-to-end) on top of the
mechanical wins above.

## SIMD with `V128` (experimental)

`moonbitlang/core/v128` exposes the built-in 128-bit vector type `V128` with
~265 free functions mirroring the wasm SIMD128 opcode set 1:1: lane families
`i8x16` / `i16x8` / `i32x4` / `i64x2` / `f32x4` / `f64x2` with
`*_const` / `*_splat` / `*_extract_lane` / `*_replace_lane`, integer/float
arithmetic, compares, shifts, extends, and `v128_load*` ops over
`FixedArray[Byte] + offset`. Import `"moonbitlang/core/v128"` and call free
functions — `@v128.i8x16_add(a, b)`, `@v128.i64x2_const(lo, hi)`. There is no
method style (`a.i8x16_add(b)` was briefly added upstream and then removed).

Caveats:

- **Experimental**: every op is `#internal(experimental, "subject to breaking
  change without notice")` — expect alerts when calling it from application
  code, and expect the API to move.
- **Hidden from `.mbti`**: ops are `#doc(hidden)`, so `pkg.generated.mbti`
  shows only the `V128` trait impls. To see the current op list, read the
  source under `${MOON_HOME}/lib/core/v128/` (`simd_*.mbt`) — do not conclude
  "no API" from the interface file.
- Ops carry `#intrinsic("%v128...")` fast paths with portable MoonBit fallback
  bodies, so code compiles on all backends and is accelerated where the
  backend supports the intrinsic. Benchmark before/after as with any other
  hot-path change.

## What is *not* worth doing

- **Manual branchless rewrites of `if cond { x |= bit }`.** clang already
  lowers these to `csel`/`orr` at `-O2` — verified in arm64 asm. The
  source-level `if` is just how you express a conditional OR; the machine
  code is branchless. Hand-rolling it changes nothing but readability.
- **Chasing predictable branches.** A bounds-check panic or a guard around a
  cold path (e.g. a rare full rescan) is predicted not-taken and ≈free. Keep
  the branch that guards a call; don't go branchless to "remove" it.
- **Eliminating a duplicated bounds check on the same local + unchanged
  index.** The backend won't coalesce it, but it's one well-predicted
  compare; removing it needs `unsafe` indexing — rarely worth the safety
  loss.

## Checklist

- [ ] Profiled; identified the real hot function (and any `<- decref/incref`
      leaf cost attributed to it).
- [ ] Read the generated C for that function; refcount ops and polymorphic
      `Eq` calls accounted for.
- [ ] Hot enum compares are `is`/`match`, not `!=`/`==`.
- [ ] No heap value held live across a call between an indexed load and store.
- [ ] Common-case fast paths guard out fast-returning calls.
- [ ] Hot cross-package leaves are single branchless expressions.
- [ ] Measured before/after as means of 3–4 runs each, not single runs.
- [ ] `moon fmt` + `moon info`; intended `.mbti` change only.
