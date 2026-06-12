# `#valtype` — Unboxed Value Types

`#valtype` is a native-backend optimization attribute. Reach for it only when
profiling or layout analysis shows boxing/allocation is a cost — eliminating
per-value heap allocation in a hot path, or making a large `Array[T]` flat
instead of an array of pointers. It changes representation, not semantics.

All claims below were verified by reading generated C (`_build/<target>/<mode>/build/<pkg>/<pkg>.c`,
see `toolchain.md`). When in doubt, re-verify the same way — the rules are
strict and the error messages are the ground truth.

## What it does

- A `#valtype` struct/enum is **stack-allocated / stored inline** on the native
  target instead of being a heap object behind a pointer. No per-value `malloc`,
  no refcount drop.
- `Array[T]` of a `#valtype T` is a **flat scalar array** (one contiguous
  buffer, no per-element box or pointer) via `moonbit_make_scalar_valtype_array`.
- It is a **native-backend** concern; on JS/wasm it is a no-op layout hint.
- `#valtype` does **not** appear in `.mbti` — it is an internal representation
  detail, so adding/removing it never changes the public API.

## Gotcha: `Byte`/small fields are NOT sub-word packed

Each field still occupies a full machine slot. `#valtype struct { r:Byte; g:Byte; b:Byte }`
compiles to a struct of **three `int32_t` = 12 bytes**, not 3. To get a compact
value, pack the fields yourself into one `UInt` (4 bytes) and decode in
accessors:

```moonbit
pub struct RGB(UInt)                            // 4 bytes, transparent scalar
pub fn RGB::new(r : Byte, g : Byte, b : Byte) -> RGB {
  RGB((r.to_uint() << 16) | (g.to_uint() << 8) | b.to_uint())
}
pub fn RGB::r(self : RGB) -> Byte { ((self.0 >> 16) & 0xFFU).to_byte() }
```

A **newtype over a scalar is itself a transparent scalar**: `struct RGB(UInt)`
compiles so that `RGB::new` literally returns `uint32_t` — there is no wrapper
struct. This is the key building block for the rules below.

## Field / payload rules (strict — these are compile errors)

The two containers have *different* rules. A "scalar" is a primitive
(`Int`/`UInt`/`Byte`/…) or a newtype over a scalar. A plain (non-`#valtype`)
struct/enum is a **reference** (a pointer).

### `#valtype` struct

Two restrictions:

1. **All fields must be immutable** — a single `mut` field is rejected with
   `Value type is not allowed for struct with mutable field`. A value type is
   copied by value, so in-place mutation has no meaning; model updates as
   functional `with_*` helpers that return a new value.
2. **No field may be another `#valtype` type** (struct *or* enum) — you cannot
   nest a value type inside a value type. Fields may be scalars, newtypes, or
   reference types (a plain struct/enum field is a pointer, which is fine).

| Field type | Result |
|---|---|
| scalar / newtype-over-scalar | ✅ |
| plain struct/enum (a reference/pointer field) | ✅ |
| another `#valtype` struct **or** `#valtype` enum | ❌ `Value type is not allowed for type with nested value type field` |
| any `mut` field | ❌ `Value type is not allowed for struct with mutable field` |

3. **At most 6 fields.** A 7th field is rejected with the same
   `Value type is not allowed for type with nested value type field` (4173). The
   cap is on **field count, not bytes**: 6× `UInt64` (48 B) is fine, 7× `Byte`
   is not. A pointer field (reference type / `Array?`) counts as one field, same
   as a scalar. To stay under the cap, pack several logical values into one wide
   field yourself (e.g. two 26-bit colors + flags into one `UInt64`) and decode
   in accessors — same trick as the `Byte`-packing gotcha above, applied to
   field *count*.

### `#valtype` enum

Stricter: every payload must be a **scalar** (or newtype-over-scalar). **No
struct payloads at all.**

| Payload type | Result |
|---|---|
| scalar / newtype-over-scalar (e.g. `Rgb(RGB)` where `RGB` is `struct RGB(UInt)`) | ✅ |
| plain struct | ❌ `Value type is not allowed for enum type with non-scalar field` |
| `#valtype` struct | ❌ `Value type is not allowed for type with nested value type field` |

A `#valtype` enum stays fully **pattern-matchable** (`match c { None => … ; Rgb(rgb) => … }`)
and the payload binds the real type (e.g. a real `RGB`). Its layout is
`{ uint32_t tag; uint32_t size; union { … } payload; }` — note the extra `size`
word, so a small value enum is ~12 bytes, not "two words". You gain *no
allocation*, not minimal size.

A **plain (reference) struct may freely hold `#valtype` fields** — only value
*containers* are restricted. (E.g. a normal heap `CellStyle` can store inline
`#valtype StyleColor` fields with zero sub-object boxes.)

## The visibility interaction (the part that bites cross-package)

To use a type `T` as a `#valtype` struct field or enum payload **from another
package**, the compiler must see `T`'s representation — so `T` cannot be
abstract:

```
Value type is not allowed for using abstract type as field type
```

This collides with the usual "keep types opaque" guidance. For a newtype you
have a useful middle setting:

| Declaration | Cross-pkg `#valtype` payload? | External `.0` / destructure read | External raw construct `T(x)` |
|---|---|---|---|
| `struct RGB(UInt)` (abstract) | ❌ abstract-type error | ❌ | ❌ |
| `pub struct RGB(UInt)` | ✅ | ✅ (representation readable) | ❌ blocked (error 4036) |
| `pub(all) struct RGB(UInt)` | ✅ | ✅ | ✅ |

So **`pub` (not `pub(all)`) on a newtype** = "representation visible enough to
be a cross-package value payload and to read `.0`, but construction stays
controlled by your `T::new`." That is usually the right dial when you want a
packed value type to be carried by a value enum in another package without
fully re-opening construction. The cost is that the packing layout becomes
externally observable (read-only).

## Worked path (packing a tagged color)

Goal: a `StyleColor = None | Palette(Byte) | Rgb(RGB)` that is unboxed yet still
pattern-matchable across packages.

1. Make `RGB` constructor-only first: `pub(all) struct RGB {…}` →
   `struct RGB {…}` (abstract), converting external `{ r, g, b }` literals to
   `RGB::new(…)`. This decouples API from representation.
2. Flip representation: `struct RGB(UInt)` newtype (now a transparent scalar).
   In-package literals must also become `RGB::new`.
3. Expose just enough: `pub struct RGB(UInt)` so other packages can carry it in
   a value enum (construction still via `RGB::new`).
4. `#valtype enum StyleColor { None; Palette(Byte); Rgb(RGB) }` — unboxed,
   still matchable, `Rgb` binds a real `RGB`. Writing a non-default color no
   longer allocates.

## Verifying

Read the generated C (`toolchain.md` → Build artifacts):

- Transparent newtype: the constructor returns the bare scalar, e.g.
  `uint32_t …RGB3new(int32_t, int32_t, int32_t)`.
- `#valtype` enum: `struct …StyleColor { uint32_t tag; uint32_t size; union {…} payload; }`.
- Flat array: allocation site shows `moonbit_make_scalar_valtype_array_raw(n, sizeof(T))`.
- If a field/payload is still boxed, you'll see a `T*` pointer in the struct
  instead of an inline `T`.
