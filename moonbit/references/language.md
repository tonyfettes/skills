# MoonBit Language Reference

Authoritative syntax reference for writing MoonBit code. Load this before writing any MoonBit syntax you have not recently verified — the language has evolved, and training-era syntax is often wrong.

This file covers the core: gotchas, core facts, primitives, reference semantics, `letrec`, and label/optional parameters. Sibling files — load them alongside this one when relevant:

| Topic | File |
|---|---|
| struct / enum / `extenum` / newtype / derive, visibility, pattern matching | `types.md` |
| `String`/`StringView` (UTF-16 safety, interpolation, `<+`/`<?`), regex | `strings-regex.md` |
| Arrays, `Map`, views, spread, `Iter` | `collections.md` |
| `Bytes`, byte containers, bitstring patterns | `bytes.md` |
| Error handling (`suberror`, `raise`/`catch`/`noraise`, `raise?`, `try`) | `errors.md` |
| Control flow (`for` / functional `loop` / `while`, pipes, loop invariants, `defer`) | `control-flow.md` |
| Methods, traits, trait objects, operator overloading | `traits-methods.md` |

---

## Must-know gotchas

Real bugs caused by training-era syntax or surprising behaviors. Read these first.

### Positional struct field access

Access positional fields with `.0`, `.1`, etc. — NOT `._`:

```mbt nocheck
struct UserId(Int64)
let u = UserId(42L)
let raw = u.0     // ✓ correct
// let raw = u._  // ✗ wrong — not valid MoonBit
```

### Prefer tuple-struct newtypes

For a newtype that simply wraps one existing type, prefer a tuple struct:

```mbt nocheck
struct UserId(Int64)
let id = UserId(42L)
let raw = id.0
```

This is the encouraged representation over:
- a single-variant enum
- a single-field named struct used only as a wrapper

Use tuple-struct newtypes unless you need a different representation for a
clear API or matching reason.

### Default to the smallest public surface

When designing MoonBit APIs, start from the smallest visibility that works:

- `fn` is private by default; keep it that way unless callers outside the
  package need it
- `struct` / `enum` without `pub` are the default choice for exported-but-opaque
  types
- use `priv` when the type name itself should not appear in `.mbti`
- `pub struct` is for readable, pattern-matchable data carriers
- `pub(all)` is rare; use it only when outside construction is part of the API
- public mutable fields are almost always a design mistake
- white-box tests do not justify making internals public

Practical rule:

- implementation machinery such as state machines, parse tables, accumulators,
  caches, and helper parsers should stay internal
- semantic values and deliberate host-facing contracts may be public

Always verify the result with `moon info` and review `.mbti` as an API surface,
not just as generated churn.

### Record update: `{ ..base, field: value }`

To build a struct value from an existing one with a few fields changed, use the
functional-update spread — **two dots** (`..`), not JS's three:

```moonbit
struct Style { fg : Color; bg : Color; flags : UInt } derive(Eq)

fn Style::with_fg(self : Style, fg : Color) -> Style { { ..self, fg } }
fn Style::with_flags(self : Style, flags : UInt) -> Style { { ..self, flags, } }
```

- The `..base` part copies every field of `base`; the listed fields override it.
- Field shorthand works (`{ ..self, fg }` when a local `fg` is in scope), and a
  trailing comma is allowed (`{ ..self, flags, }`).
- This is the idiom for "mutating" an immutable struct: each `with_*` returns a
  new value. On a `#valtype` struct the new value and any chain temporaries are
  stack copies, not allocations (see `valtype.md`).

### Newtypes wrapping closures are callable

Single-field struct newtypes wrapping a closure type are **directly callable**:

```mbt nocheck
pub struct Emit[Msg]((Msg) -> Cmd)
// Call: emit(Increment)  — NOT (emit.0)(Increment)
```

### No cross-package extension methods

You CANNOT define methods on types from other packages. `T::m` can only be defined in the package that owns `T`.

```mbt nocheck
// ✗ ERROR — cannot define @gio.InputStream::on_line from outside @gio
pub fn @gio.InputStream::on_line(...) { ... }
```

Instead:
- **Free function**: `pub fn on_line(stream : @gio.InputStream, ...)` — called as `@mypkg.on_line(stream, ...)`
- **Trait impl**: define a trait in your package and `impl Trait for @gio.InputStream`
- **Newtype wrapper**: `pub type MyStream @gio.InputStream` — then add methods on `MyStream`

### Module-level constants: `const PascalCase`

Use `const PascalCase` for module-level compile-time constants (strings, numbers). `const` requires an **uppercase** identifier — lowercase forces `let`:

```mbt nocheck
const DefaultScopes : Array[String] = ["read", "write"]  // ✓ correct
const PI : Double = 3.14159                              // ✓ also common: UPPER_SNAKE
// let default_scopes : Array[String] = [...]            // ✗ outdated for new code
```

### Prefer `unwrap_or` over `match Some/None`

```mbt nocheck
// ✗ verbose
let value = match opt { Some(x) => x; None => fallback }
// ✓ idiomatic
let value = opt.unwrap_or(fallback)
let mapped = opt.map(v => v.field).unwrap_or(default)
// Also: unwrap_or_else, unwrap_or_default, map_or, map_or_else
```

When branches do have real logic, still don't `match` an Option — use
`if x is Some(v) { ... } else { ... }` for branching, or
`guard x is Some(v) else { ... }` for early exit. Reserve `match` for enums
with several meaningful arms.

### `guard` without `else` panics

`guard cond` / `guard x is Pattern` with **no `else`** panics at runtime when
the condition fails. Treat it with the same severity as `abort`: do not
introduce it without explicit user confirmation. Default to writing the `else`
branch — early return, typed error, or fallback value:

```mbt nocheck
guard queue.pop() is Some(job) else { return }   // ✓ explicit failure path
guard queue.pop() is Some(job)                   // ✗ panics if empty — needs user sign-off
```

This applies **in tests too** — prefer raising over panicking, e.g.
`guard parsed is Some(v) else { fail("parse failed: \{input}") }`, not a bare
`guard parsed is Some(v)`.

### String indexing is UTF-16; slicing can crash

`String[i]` returns a `UInt16` (UTF-16 code unit), NOT a `Char`:

```mbt nocheck
let s = "hello"
let b0 : UInt16 = s[0]                 // code unit
let c0 : Char? = s.get_char(0)          // option<char>
```

`String[i]` is also not a safe general-purpose text operation. Direct indexing
and `s[a:b]` slicing can abort or raise at UTF-16 surrogate boundaries. Avoid
abort-prone string operations whenever practical.

Prefer these patterns instead:

- **ASCII-only processing**:
  validate/canonicalize as ASCII first, then convert to `Bytes` and work on the
  bytes
- **Unicode-safe prefix/suffix handling**:
  use pattern matching such as `if s is [.."pre", ..rest]` or
  `if s is [..rest, .."suf"]`
- **Unicode-safe iteration**:
  use `for c in s` to iterate `Char` by `Char`

Do not default to `[]` indexing or `[:]` slicing for user text.

**Safe string truncation** — do NOT use `str[:N]` / `str.substring(end=N)` (both abort on surrogate pairs):

```mbt nocheck
if !text.char_length_ge(max + 1) { return text }
if text.offset_of_nth_char(max) is Some(offset) {
  text.view(end_offset=offset).to_string() + "..."
} else {
  text
}
```

### `trim`/slicing return `StringView`, not `String`

`String::trim`, `trim_start`, `trim_end` (`trim_space` is deprecated — use
`trim`), and `[a:b]` slicing all
return a **`StringView`** (a borrowed slice — no allocation), not a `String`:

```mbt nocheck
let v : @string.StringView = "  hi  ".trim()   // StringView, not String
```

This matters when you compare or pass the result:

- **Comparing against a string literal needs NO conversion.** A string literal
  infers as `StringView` when that's the expected type, so `assert_eq` /
  `==` against a literal Just Works:

  ```mbt nocheck
  assert_eq(captured.trim(), "boom: network down")   // both StringView — fine
  ```

- **To materialize an owned `String`, use `to_owned()`** (e.g. when a
  `String` field/return is required, or to escape the borrow). Do NOT use
  `to_string()` for this — on a view it's the deprecated `Show` display path and
  the compiler warns: *"Use `to_owned` to allocate an owned String from a
  StringView; use `Show::to_string` or format strings for display."*

  ```mbt nocheck
  let owned : String = captured.trim().to_owned()   // not .to_string()
  ```

Reach for `to_owned()` only when you actually need an owned `String`; otherwise
keep the view and compare/interpolate it directly.

### Async functions

MoonBit has no `await` keyword. Async functions/tests are marked with the `async` prefix:

```mbt nocheck
pub async fn fetch(...) -> Response { ... }
async test "streaming" { ... }
```

Async functions automatically can raise errors without explicitly stating `raise`.

### `moon.pkg` import alias rule

No colon syntax. Default alias is the **last path segment**:

```
import {
  "username/hello/liba"              // use @liba.foo()
  "username/hello/libb" @b           // explicit alias — use @b.foo()
}
```

Don't bother with an explicit alias if it matches the last path segment.

---


## Core facts

- **Expression-oriented**: `if`, `match`, loops return values; the last expression is the return value.
- **References by default**: Arrays/Maps/structs mutate via reference; use `Ref[T]` for primitive mutability.
- **Top-level blocks** separated by `///|`. Generate code block-by-block. For blank lines inside a `{...}` block, add a comment line after the blank (comment text optional).
- **Visibility**: `fn` is private by default. See "Access control" below.
- **Naming**: `lower_snake` for values/functions; `UpperCamel` for types/enums; enum variants start `UpperCamel`.
- **Packages**: No `import` in code files — call via `@alias.fn`. Configure imports in `moon.pkg`.
- **Placeholders**: `...` is a valid placeholder for incomplete implementations.
- **Global values**: immutable by default; generally require type annotations.
- **Garbage collection**: MoonBit has a GC — no lifetime annotations, no ownership system. Unlike Rust (like F#), `let mut` is only needed when you want to **reassign** a variable — NOT for mutating fields of a struct or elements of an array/map.
- **Toplevel functions are mutually recursive by default** — no need for forward declarations. Local functions are not: use `letrec f = .. and g = ..` (see below).
- **Ranges**: `a..<b` (exclusive) / `a..=b` (inclusive) iterate increasing; **decreasing** ranges are `a>..b` (excludes `a`) and `a>=..b` (includes `a`) — `for i in 3>..0` yields `2, 1, 0`; `for i in 3>=..0` yields `3, 2, 1, 0`.

---


## Primitives: Int, Char, Byte

MoonBit supports `Byte`, `Int16`, `Int`, `UInt16`, `UInt`, `Int64`, `UInt64`, `Float`, `Double`, etc. Literals overload when the type is known:

```mbt check
///|
test "integer/char literal overloading via context" {
  let a0 = 1 // Int by default
  let (int, uint, uint16, int64, byte) : (Int, UInt, UInt16, Int64, Byte) = (
    1, 1, 1, 1, 1,
  )
  assert_eq(int, uint16.to_int())
  let a1 : Int = 'b'    // unicode value
  let a2 : Char = 'b'
}
```

### `Char` ASCII casing

For ASCII-only casing, use:

- `Char::to_ascii_lowercase`
- `Char::to_ascii_uppercase`

If you need full Unicode case conversion or locale-sensitive text transforms,
do not guess or hand-roll it. Use a dedicated library only after confirming
with the user.

### Numeric literal forms & BigInt

`0b`/`0o`/`0x` prefixes (case-insensitive), underscores **anywhere** in the
number (not just every three digits), and suffixes `U` (`UInt`), `L` (`Int64`),
`UL` (`UInt64`), `N` (`BigInt`). `BigInt` is arbitrary-precision; plain
literals also overload to it when the type is known.

```mbt check
///|
test "numeric literal forms" {
  let bin = 0b110010                    // 50
  let oct = 0o377                       // 255
  let hex = 0xFF_FF                     // underscores anywhere, not just per-3
  let i64 : Int64 = 42L
  let u : UInt = 42U
  let u64 : UInt64 = 42UL
  let big : BigInt = 10000000000000000000000N
  let big2 : BigInt = 42                // plain literal overloads to BigInt too
  inspect(big * big2, content="420000000000000000000000")
  ignore((bin, oct, hex, i64, u, u64))
}
```


## Reference semantics

MoonBit passes most types by reference semantically (optimizer may copy immutables). No `mut` needed on parameters to mutate their fields:

```mbt check
///|
struct Counter {
  mut value : Int
}

///|
fn increment(c : Counter) -> Unit {
  c.value += 1                                // modifies the original
}

///|
fn modify_array(arr : Array[Int]) -> Unit {
  arr[0] = 999                                // modifies original array (no `mut` param)
}

///|
test "reference semantics" {
  let counter : Ref[Int] = Ref::{ val: 0 }
  counter.val += 1
  assert_true(counter.val is 1)

  let arr : Array[Int] = [1, 2, 3]            // no `mut` keyword
  modify_array(arr)
  assert_true(arr[0] is 999)

  let mut x = 3                               // `mut` needed for reassignment of binding
  x += 2
  assert_true(x is 5)
}
```

---


## Local mutually recursive functions: `letrec`

Toplevel functions see each other freely, but a **local** `fn` can only refer to itself and to local functions defined *before* it. For local mutual recursion, use `letrec ... and ...`:

```mbt check
///|
test "letrec" {
  letrec even = x => x == 0 || odd(x - 1)
  and odd = x => x != 0 && even(x - 1)
  assert_true(even(10))
  assert_true(odd(7))
}
```

---


## Label and optional parameters

```mbt check
///|
fn g(
  positional : Int,
  required~ : Int,
  optional? : Int,                            // no default => Option
  optional_with_default? : Int = 42,          // default => plain Int
) -> String {
  let _ : Int = positional
  let _ : Int = required
  let _ : Int? = optional
  let _ : Int = optional_with_default
  "\{positional},\{required},\{to_repr(optional)},\{optional_with_default}"
}

///|
test {
  inspect(g(1, required=2), content="1,2,None,42")
  inspect(g(1, required=2, optional=3), content="1,2,Some(3),42")
  inspect(g(1, required=4, optional_with_default=100), content="1,4,None,100")
}
```

**Misuse**: `arg : Type?` is NOT an optional parameter. Callers still must pass `None` / `Some(...)`:

```mbt check
///|
fn with_config(a : Int?, b : Int?, c : Int) -> String {
  "\{to_repr(a)},\{to_repr(b)},\{c}"
}

///|
test {
  inspect(with_config(None, None, 1), content="None,None,1")
  inspect(with_config(Some(5), Some(5), 1), content="Some(5),Some(5),1")
}
```

**Anti-pattern**: `arg? : Type?` (no default => double Option). If you want a defaulted optional, write `b? : Int = 1`, NOT `b? : Int? = Some(1)`:

```mbt check
///|
fn f_misuse(a? : Int?, b? : Int = 1) -> Unit {
  let _ : Int?? = a                           // rarely intended
  let _ : Int = b
}

///|
fn f_correct(a? : Int, b? : Int = 1) -> Unit {
  let _ : Int? = a
  let _ : Int = b
}
```

**Also bad**: `arg : APIOptions` struct-of-options — use labeled optional parameters instead:

```mbt check
///|
struct APIOptions {
  width : Int?
  height : Int?
}

///|
fn not_idiomatic(opts : APIOptions, arg : Int) -> Unit { }

///|
test {
  not_idiomatic({ width: Some(5), height: None }, 10)          // awkward at call site
}
```

### Autofill arguments: `SourceLoc` / `ArgsLoc`

`#callsite(autofill(...))` makes the compiler fill listed labelled arguments at each call site when the caller omits them. Two supported types: `SourceLoc` (location of the whole call) and `ArgsLoc` (per-argument locations). This is how `assert_eq`/`inspect` report caller locations — the key tool for writing assertion/test helpers:

```mbt check
///|
#callsite(autofill(loc, args_loc))
fn where_am_i(msg : String, loc~ : SourceLoc, args_loc~ : ArgsLoc) -> String {
  "\{msg} at \{loc}; args at \{args_loc}"
}

///|
test "autofill" {
  let s = where_am_i("boom")                  // loc/args_loc filled automatically
  assert_true(s.contains(".mbt"))
}
```
