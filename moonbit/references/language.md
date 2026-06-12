# MoonBit Language Reference

Authoritative syntax reference for writing MoonBit code. Load this before writing any MoonBit syntax you have not recently verified — the language has evolved, and training-era syntax is often wrong.

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
pub struct Dispatch[Msg]((Msg) -> Cmd)
// Call: dispatch(Increment)  — NOT (dispatch.0)(Increment)
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

Reserve full `match` for cases where each branch has real logic, not "return value / return default".

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
match text.offset_of_nth_char(max) {
  Some(offset) => text.view(end_offset=offset).to_string() + "..."
  None => text
}
```

### `trim`/slicing return `StringView`, not `String`

`String::trim`, `trim_start`, `trim_end`, `trim_space`, and `[a:b]` slicing all
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
- **Toplevel functions are mutually recursive by default** — no need for forward declarations.

---

## Access control

Fine-grained visibility modifiers.

```mbt nocheck
///|
/// `fn` defaults to private — only visible in current package
fn internal_helper() -> Unit { ... }

///|
pub fn get_value() -> Int { ... }

///|
/// Struct (default) — type visible outside package as abstract, implementation hidden
struct DataStructure { }

///|
/// `priv struct` — fully hidden: name unreferenceable outside the package
priv struct Secret { }

///|
/// `pub struct` — readable and pattern-matchable outside package, NOT constructible outside
pub struct Config { }

///|
/// `pub(all)` — full access: read, pattern match, AND construct outside
pub(all) struct Config2 { }

///|
/// Abstract trait (default) — cannot be implemented by types outside this package
pub trait MyTrait { }

///|
/// `pub(open)` — trait CAN be implemented for outside packages
pub(open) trait Extendable { }
```

**Public cannot depend on `priv`** — `pub struct X(Inner)` (or `pub fn` signatures) referencing a `priv Inner` fails with `[4046] A public definition cannot depend on private type`. Default `struct` (no modifier) is already abstract to outside packages, so it works as the inner of a `pub` newtype. Only reach for `priv` when you want the type name itself completely unnameable from other packages — and in that case, drop `pub` on the wrapper too and export it via `pub fn X::new(...)` methods (the type becomes opaque in the `.mbti`).

### Visibility design heuristics

Use this decision order when choosing visibility:

1. If the item is purely implementation detail, keep it private.
   Use `priv` for helper types whose names should not appear in public
   signatures or `.mbti`.
2. If outside code only needs to hold/pass the value and call methods, prefer
   opaque `struct` / `enum` without `pub`.
3. If outside code needs to inspect fields or pattern-match variants, use
   `pub struct` / public enum deliberately.
4. If outside code must also construct the value directly, consider `pub(all)`,
   but treat that as a stronger API promise.

Review `.mbti` after `moon info` with this lens:

- Could this public item be private?
- Could this readable type be opaque instead?
- Is a public mutable field really necessary?
- Is this item public only because tests currently touch it?

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

## Bytes (immutable)

```mbt check
///|
test "bytes literals and indexing" {
  let b0 : Bytes = b"abcd"
  let b1 : Bytes = "abcd"                   // b" prefix optional when type known
  let b2 : Bytes = [0xff, 0x00, 0x01]       // array literal overloading
  guard b0 is [b'a', ..] && b0[1] is b'b' else {
    fail("unexpected bytes content")
  }
}
```

## Array (resizable), FixedArray, ReadOnlyArray, ArrayView

```mbt check
///|
test "array literals" {
  let a0 : Array[Int] = [1, 2, 3]           // resizable
  let a1 : FixedArray[Int] = [1, 2, 3]      // fixed size
  let a2 : ReadOnlyArray[Int] = [1, 2, 3]
  let a3 : ArrayView[Int] = [1, 2, 3]
}
```

## String (immutable UTF-16)

`s[i]` returns a **code unit (UInt16)** — NOT a Char. Use `s.get_char(i)` for `Char?`.

```mbt check
///|
test "string indexing and utf8 encode/decode" {
  let s = "hello world"
  let b0 : UInt16 = s[0]
  guard b0 is ('\n' | 'h' | 'b' | 'a'..='z') && s is [.. "hello", .. rest] else {
    fail("unexpected string content")
  }
  guard rest is " world"                   // crashes on mismatch (no `else`)

  let b1 : Char? = s.get_char(0)
  assert_true(b1 is Some('a'..='z'))

  // ⚠️ variables don't work with direct indexing
  let eq_char : Char = '='
  // s[0] == eq_char // ❌ eq_char not a literal; s[0] is UInt16
  // Use: s[0] == '=' or s.get_char(0) == Some(eq_char)

  let bytes = @utf8.encode("中文")
  assert_true(bytes is [0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87])
  let s2 : String = @utf8.decode(bytes)
  assert_true(s2 is "中文")
  for c in "中文" {
    let _ : Char = c                        // unicode-safe iteration
    println("char: \{c}")
  }
}
```

### String interpolation && StringBuilder

`\{expr}` for interpolation; custom types must implement `Show`:

```mbt check
///|
test "string interpolation" {
  let name : String = "Moon"
  let config = { "cache": 123 }
  let version = 1.0
  println("Hello \{name} v\{version}")

  // Quoted map keys are allowed inside interpolation expressions.
  println("'cache' section: \{config["cache"]}")

  let sb = StringBuilder()
  sb <+ "[\{[ for x in [1, 2, 3] => "\{x}" ].join(",")}]"
  inspect(sb, content="[1,2,3]")

  let x = 42
  let streamed = StringBuilder()
  streamed <+ "hello \{x}"
  inspect(streamed, content="hello 42")
}
```

Expressions inside `\{}` must be single-line expressions. Nested
interpolations and string literals are supported, but line breaks inside `\{}`
are not.

String interpolation can also be streamed directly into a
`Logger`/`StringBuilder`-style writer with `<+`:

```mbt nocheck
writer <+ "hello \{x}"
```

This expands to calls on the writer:

```mbt nocheck
writer.write_string("hello ")
writer.write(x)
```

Literal string segments use `write_string`; interpolated expressions use
`write`. The expansion is macro-style: it depends on how the writer type
implements `write_string` and `write`. Types such as HTMLBuilder or JSONBuilder
can support interpolation and streaming with the same syntax but different
semantics.

### Multi-line strings

```mbt check
///|
test "multi-line string literals" {
  let a : String =
    #|Hello "world"
    #|World
    #|
  let b : String =
    $|Line 1 ""
    $|Line 2 \{1+2}
    $|
  // `#|` — no escape. `$|` — only escape `\{..}`.
  assert_eq(a, "Hello \"world\"\nWorld\n")
  assert_eq(b, "Line 1 \"\"\nLine 2 3\n")
}
```

## Map (mutable, insertion-order preserving)

```mbt check
///|
test "map literals and common operations" {
  let map : Map[String, Int] = { "a": 1, "b": 2, "c": 3 }
  let empty : Map[String, Int] = {}                     // preferred over Map::new()
  let also_empty : Map[String, Int] = Map::new()
  let from_pairs : Map[String, Int] = Map::from_array([("x", 1), ("y", 2)])

  map["new-key"] = 3
  map["a"] = 10

  guard map is { "new-key": 3, "missing"? : None, .. } else {
    fail("unexpected map")
  }
  let value : Int = map["a"]                 // panics if missing

  for k, v in map {
    println("\{k}: \{v}")                    // insertion order preserved
  }

  map.remove("b")
  guard map is { "a": 10, "c": 3, "new-key": 3, .. } && map.length() == 3 else {
    fail("unexpected map after removal")
  }
}
```

## View types

Zero-copy, non-owning read-only slices created with `[:]` syntax. No allocation. Functions taking `String`/`Bytes`/`Array` also accept `*View` (implicit conversion).

- `String` → `StringView` via `s[:]`, `s[start:end]`, `s[start:]`, `s[:end]`
- `Bytes` → `BytesView` via `b[:]`, `b[start:end]`, etc.
- `Array[T]` / `FixedArray[T]` / `ReadOnlyArray[T]` → `ArrayView[T]` via `a[:]`, etc.

**StringView caveat**: `s[a:b]` may raise at surrogate boundaries (UTF-16 edge case). Use `try! s[a:b]` if certain, or propagate the error.

Use views for:
- Rest patterns (`[first, .. rest]`)
- Passing slices without allocation
- Avoiding copies of large sequences

Convert back with `.to_string()`, `.to_bytes()`, `.to_array()` when you need ownership.

---

## User-defined types

### struct

```mbt check
///|
struct Point {
  x : Int
  mut y : Int                                // `mut` allows field mutation
} derive(Show, ToJson, Eq)

///|
/// `Type::` can be omitted when the type is already known in context
let p : Point = Point::{ x: 10, y: 20 }

///|
/// pub(all) — readable AND constructible outside the package
pub(all) struct Config {
  host : String
  port : Int
} derive(Show, Eq, ToJson, FromJson)
```

### enum

```mbt check
///|
enum Tree[T] {
  Leaf(T)                                           // no trailing comma
  Node(left~ : Tree[T], T, right~ : Tree[T])        // variants can use labels
} derive(Show, ToJson)

///|
pub enum MyResult[T, E] {
  MyOk(T)                                           // semicolon optional when newline follows
  MyErr(E)                                          // variants must start Uppercase
} derive(Show, Eq, ToJson)

///|
pub fn Tree::sum(tree : Tree[Int]) -> Int {
  match tree {
    Leaf(x) => x                                    // no `Tree::` needed when type known
    Node(left~, x, right~) => left.sum() + x + right.sum()
  }
}
```

### Newtype / tuple-struct

Single-field structs with positional syntax. Access via `.0`, `.1`, etc.

```mbt check
///|
struct Meters(Int)

///|
let distance : Meters = Meters(100)

///|
let raw : Int = distance.0                 // .0 for first positional field

///|
/// Newtype wrapping a closure — directly callable
pub struct Handler((String) -> Unit)
// let h : Handler = Handler(s => println(s))
// h("hello")                                // calls the closure directly
```

### Type alias

```mbt nocheck
pub type UserId = Int                       // Int is aliased to UserId (symlink-like)
```

### Derivable traits

Most types can auto-derive standard traits with `derive(...)`:

| Trait | Enables |
|---|---|
| `Show` | `to_string()`, string interpolation `\{value}` |
| `Eq` | `==`, `!=` |
| `Compare` | `<`, `>`, `<=`, `>=` |
| `ToJson` | `@json.inspect()` for readable test output |
| `FromJson` | JSON deserialization |
| `Hash` | Map keys |

```mbt check
///|
struct Coordinate {
  x : Int
  y : Int
} derive(Show, Eq, ToJson)

///|
enum Status {
  Active
  Inactive
} derive(Show, Eq, Compare)
```

**Best practice**: always derive `Show` and `Eq` for data types; add `ToJson` if you test them with `@json.inspect()`.

---

## Pattern matching

Match expressions return values. Extensive patterns on arrays, structs, strings.

```mbt check
///|
#warnings("-unused_value")
test "pattern matching on Array, struct, StringView" {
  let arr : Array[Int] = [10, 20, 25, 30]
  match arr {
    [] => ...                                        // empty
    [single] => ...                                  // single element
    [first, .. middle, rest] => {
      let _ : ArrayView[Int] = middle                // middle is ArrayView[Int]
      assert_true(first is 10 && middle is [20, 25] && rest is 30)
    }
  }

  fn process_point(point : Point) -> Unit {
    match point {
      { x: 0, y: 0 } => ...
      { x, y } if x == y => ...
      { x, .. } if x < 0 => ...
      ...
    }
  }

  fn is_palindrome(s : StringView) -> Bool {
    loop s {
      [] | [_] => true
      [a, .. rest, b] if a == b => continue rest    // a, b are Char; rest is StringView
      _ => false
    }
  }
}
```

---

## Error handling (checked errors)

MoonBit uses checked error-throwing, not unchecked exceptions. All errors are subtypes of `Error`; declare custom types with `suberror`. Checked errors are tracked in function signatures, not marked at every call site — a function that may raise declares `raise` or `raise SomeError`. Errors propagate by default — **do NOT add `try`** for functions that raise (unlike Swift). Use:
- Plain call inside a `raise` function — propagates automatically.
- `expr catch { ... }` or `try { } catch { } [noraise { }]` — handle explicitly.
- `try! expr` — abort if it raises.

Do not use the legacy `function_name!(...)` / `function_name(...)?` syntax for new code. (`try?`, which converts to `Result[_, _]`, is being deprecated — prefer `try ... catch ... noraise` instead.)

```mbt check
///|
suberror ValueError {
  ValueError(String)
}

///|
struct Position(Int, Int) derive(ToJson, Show, Eq)

///|
pub(all) suberror ParseError {
  InvalidChar(pos~ : Position, Char)
  InvalidEof(pos~ : Position)
  InvalidNumber(pos~ : Position, String)
  InvalidIdentEscape(pos~ : Position)
} derive(Eq, ToJson, Show)

///|
fn parse_int(s : String, position~ : Position) -> Int raise ParseError {
  if s is "" {
    raise ParseError::InvalidEof(pos=position)
  }
  ...
}

///|
/// Just `raise` (no type) — don't track specific error type
fn div(x : Int, y : Int) -> Int raise {
  if y is 0 { fail("Division by zero") }
  x / y
}

///|
test "inspect raise function" {
  // Expected-failure shape: handle in `catch`, fail explicitly in `noraise`.
  try div(1, 0) catch {
    Failure(msg) => assert_true(msg.contains("Division by zero"))
    _ => fail("unexpected error")           // catch must be exhaustive over Error
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
/// Errors propagate automatically — no `try` needed
fn use_parse(position~ : Position) -> Int raise ParseError {
  let x = parse_int("123", position~)
  x * 2
}

///|
/// Convert to a Result by catching explicitly (replaces the deprecated `try?`)
fn safe_parse(s : String, position~ : Position) -> Result[Int, ParseError] {
  try parse_int(s, position~) catch {
    err => Err(err)
  } noraise {                                        // noraise block runs on success
    v => Ok(v)
  }
}

///|
/// try-catch with specific patterns
fn handle_parse(s : String, position~ : Position) -> Int {
  try parse_int(s, position~) catch {
    ParseError::InvalidEof(pos=_) => {
      println("Parse failed: InvalidEof")
      -1
    }
    _ => 2
  }
}
```

All `async` functions can raise errors without explicitly stating `raise`.

### Error polymorphism: `raise?` and `noraise`

A higher-order function whose own raising depends on its callback's raising must use `raise?`. The compiler resolves `raise?` to `raise` or `noraise` at each call site based on the callback type:

```mbt nocheck
fn[T] map(arr : Array[T], f : (T) -> T raise?) -> Array[T] raise? {
  let res = []
  for x in arr { res.push(f(x)) }
  res
}

fn pure(arr : Array[Int]) -> Array[Int] noraise {
  map(arr, x => x + 1)              // f is noraise → map call site is noraise
}

fn fallible(arr : Array[Int]) -> Array[Int] raise {
  map(arr, x => if x < 0 { fail("neg") } else { x })   // f raises → map call site raises
}
```

Without `raise?`, `map` would unconditionally appear to raise, polluting all callers. Use `raise?` whenever a function's raising is purely "as-raising-as my callback".

`noraise` makes the no-raise contract explicit on a signature. You'll see it most often on `async` functions (which otherwise raise implicitly):

```mbt nocheck
async fn pure_async() -> Int noraise { 42 }
```

### `Error` bound on generics

To write a function generic in the *concrete* error type (not just `Error`), bind a type parameter with `: Error`:

```mbt nocheck
fn[T, E : Error] unwrap_or_error(r : Result[T, E]) -> T raise E {
  match r {
    Ok(x)  => x
    Err(e) => raise e
  }
}
```

This preserves the specific error type at call sites — better than the catch-all `raise` (which is `raise Error`) when callers want to handle one variant.

### `try` block error inference

Inside a `try` block, multiple raise types collapse to `Error`. The handler must use `_` to catch all variants and re-raise unhandled ones:

```mbt nocheck
try {
  f1()                                // raise E1
  f2()                                // raise E2
} catch {
  E1(_) => ...
  E2    => ...
  e     => raise e                    // re-raise anything else
}
```

---

## Control flow

### Expressions are values

`if`, `match`, loops all return values; the last expression is the return:

```mbt check
///|
test "expressions return values" {
  let (n, opt) = (1, Some(2))
  let msg : String = if n > 0 { "pos" } else { "non-pos" }
  let res = match opt {
    Some(x) => x + 10
    None => 0
  }
  inspect(res, content="12")
  inspect(msg, content="pos")
}
```

### Functional `for` loop

```mbt check
///|
pub fn binary_search(arr : ArrayView[Int], value : Int) -> Result[Int, Int] {
  let len = arr.length()
  // for: initial state; [predicate]; [post-update] {
  //   body — `continue` updates state
  // } else { exit block }
  for i = 0, j = len; i < j; {
    let h = i + (j - i) / 2
    if arr[h] < value {
      continue h + 1, j
    } else {
      continue i, h
    }
  } else {
    if i < len && arr[i] == value { Ok(i) } else { Err(i) }
  } where {
    invariant: 0 <= i && i <= j && j <= len,
    invariant: i == 0 || arr[i - 1] < value,
    invariant: j == len || arr[j] >= value,
    reasoning: (
      #|For a sorted array, boundary invariants are witnesses:
      #|  arr[i-1] < value implies all arr[0..i) < value (by sortedness)
      #|  arr[j] >= value implies all arr[j..len) >= value
      #|Termination: j - i decreases each iteration.
      #|Correctness at exit: arr[0..i) < value and arr[i..len) >= value.
    ),
  }
}

///|
test "iteration" {
  let arr : Array[Int] = [1, 3, 5, 7, 9]
  inspect(binary_search(arr, 5), content="Ok(2)")
  for i, v in arr {
    println("\{i}: \{v}")                    // i = index, v = value
  }
}
```

**Prefer functional `for`** over imperative. For trivial loops, use `for x in collection` — no reasoning needed.

#### Loop invariants (`where` clause)

Attaches machine-checkable invariants and human-readable reasoning:

```mbt nocheck
for ... {
  ...
} where {
  invariant : <boolean_expr>,
  invariant : <boolean_expr>,
  reasoning : <string>
}
```

Writing good invariants:
1. **Checkable** — use valid boolean expressions over loop variables.
2. **Boundary witnesses** — for "all elements in arr[0..i)" properties, check only boundary elements.
3. **Edge cases with `||`** — e.g. `i == 0 || arr[i-1] < value`.
4. **Reasoning covers three aspects** — Preservation (each `continue` maintains invariants), Termination (decreasing measure), Correctness (invariants at exit imply postcondition).

### Functional `loop` (MoonBit-specific)

Unlike `for`, `loop` pattern-matches on loop variables and uses `continue` with updated values. Great for tail-recursive-style algorithms:

```mbt check
///|
/// Pattern-match on a @list.List
fn sum_list(list : @list.List[Int]) -> Int {
  loop (list, 0) {
    (Empty, acc) => acc
    (More(x, tail=rest), acc) => continue (rest, x + acc)
  }
}

///|
/// Two-pointer search with loop
fn find_pair(arr : Array[Int], target : Int) -> (Int, Int)? {
  loop (0, arr.length() - 1) {
    (i, j) if i >= j => None
    (i, j) => {
      let sum = arr[i] + arr[j]
      if sum == target {
        Some((i, j))
      } else if sum < target {
        continue (i + 1, j)
      } else {
        continue (i, j - 1)
      }
    }
  }
}
```

**`loop` requires a payload.** For an infinite loop, use `while true { ... }` instead — `loop { ... }` without arguments is invalid.

### `while` returns a value

```mbt check
///|
test "while with break value" {
  let array = [1, 2, 3, 4, 5]
  let mut i = 0
  let target = 3
  let found : Int? = while i < array.length() {
    if array[i] == target {
      break Some(i)                          // exit with a value
    }
    i = i + 1
  } else {
    None                                     // value when loop completes normally
  }
  assert_eq(found, Some(2))
}
```

### Labelled loops

Use `label~:` before a loop and `break label~` / `continue label~` to target
that loop from a nested loop. Keep the trailing `~` on both the label
declaration and the labelled control-flow statement; `break label` is parsed as
breaking with the value `label`, not as a labelled break.

```mbt check
///|
test "labelled break" {
  let mut seen = 0
  outer~: while true {
    for x in [1, 2, 3] {
      seen = x
      if x == 2 {
        break outer~
      }
    }
  }
  assert_eq(seen, 2)
}
```

---

## Methods and traits

Methods use `Type::method_name` syntax. Traits are defined with a trait body and implemented with `impl Trait for Type`.

```mbt check
///|
struct Rectangle {
  width : Double
  height : Double
}

///|
/// Methods prefixed with Type::
fn Rectangle::area(self : Rectangle) -> Double {
  self.width * self.height
}

///|
/// Static methods don't take self
fn Rectangle::new(w : Double, h : Double) -> Rectangle {
  { width: w, height: h }
}

///|
/// Show uses `output(self, logger)` for custom formatting — to_string() is derived from this
pub impl Show for Rectangle with output(self, logger) {
  logger.write_string("Rectangle(\{self.width}x\{self.height})")
}

///|
trait Named {
  name() -> String                            // no `self` parameter — not object-safe
}

///|
/// Trait bounds in generics
fn[T : Show + Named] describe(value : T) -> String {
  "\{T::name()}: \{value.to_string()}"
}

///|
impl Hash for Rectangle with hash_combine(self, hasher) {
  hasher..combine(self.width)..combine(self.height)
}
```

### `Self` in trait bodies

Inside a trait declaration, `Self` refers to the implementing type:

```mbt nocheck
pub(open) trait Container {
  empty() -> Self                              // constructor returning Self
  push(Self, Int) -> Self
  pop(Self) -> (Self, Int)?
}
```

### Default trait methods (`= _`)

Traits can supply default method bodies. The declaration uses the `= _` marker so readers see at-a-glance which methods have defaults; the body is provided in a separate `impl T with method(...) { ... }` block:

```mbt nocheck
pub(open) trait J {
  f(Self) -> Unit
  f_twice(Self) -> Unit = _                    // default body provided below
}

impl J with f_twice(self) {
  self.f()
  self.f()
}
```

Implementers only need to provide `f` — `f_twice` is inherited. They may still override with `impl J for MyType with f_twice(...)` when the default isn't right.

For traits where every method has a default, write `impl Trait for Type` (no method clause) to register the implementation and let the compiler verify all defaults apply. This also serves as a TODO marker.

### Trait inheritance

```mbt nocheck
pub(open) trait Position { pos(Self) -> (Int, Int) }
pub(open) trait Draw     { draw(Self, Int, Int) -> Unit }
pub(open) trait Object: Position + Draw {}      // Object requires both

pub fn[O : Object] render(obj : O) -> Unit {
  let (x, y) = obj.pos()
  obj.draw(x, y)
}
```

Implementing the sub-trait requires implementing every super-trait too.

### Local methods on foreign types

You **cannot** add a `pub` method to a type from another package. But you **can** add a *private* method on a foreign type, scoped to your current package:

```mbt nocheck
fn Int::squared_plus(self : Int) -> Int { self * self + self }    // private, current package only

test {
  assert_eq((6).squared_plus(), 42)
}
```

If your method name shadows one from the type's home package, the compiler emits a warning. Use this for local extensions / convenience methods. For genuine cross-package extension, use a free function or define a trait and `impl Trait for @otherpkg.Type` instead (covered in "Must-know gotchas").

### Operator overloading

```mbt check
///|
struct Vector(Int, Int)

///|
pub impl Add for Vector with add(self, other) {
  Vector(self.0 + other.0, self.1 + other.1)
}

///|
struct Person {
  age : Int
} derive(Eq)

///|
pub impl Compare for Person with compare(self, other) {
  self.age.compare(other.age)
}

///|
test "operator overloading" {
  let v1 : Vector = Vector(1, 2)
  let v2 : Vector = Vector(3, 4)
  let _v3 : Vector = v1 + v2                 // uses impl Add
}
```

| Operator | Mechanism |
|---|---|
| `+`, `-`, `*`, `/`, `%` | trait `Add` / `Sub` / `Mul` / `Div` / `Mod` |
| `==` | trait `Eq` |
| `<<`, `>>` | trait `Shl` / `Shr` |
| `&`, <code>&#124;</code>, `^` | trait `BitAnd` / `BitOr` / `BitXOr` |
| unary `-` | trait `Neg` |
| `_[_]`, `_[_] = _`, `_[_:_]` | method + `#alias("...")` (see below) |

### Indexing operators via `#alias`

Index-shaped operators (`x[k]`, `x[k] = v`, `x[a:b]`) are overloaded by methods with an `#alias("op")` annotation, not by traits. Each has a required signature:

| Alias | Signature | Usage |
|---|---|---|
| `#alias("_[_]")` | `(Self, Index) -> Result` | `let r = self[index]` |
| `#alias("_[_]=_")` | `(Self, Index, Value) -> Unit` | `self[index] = value` |
| `#alias("_[_:_]")` | `(Self, start? : Index, end? : Index) -> Result` | `self[start:end]` |

```mbt nocheck
struct Coord {
  mut x : Int
  mut y : Int
} derive(Show)

#alias("_[_]")
fn Coord::get(self : Self, key : String) -> Int {
  match key { "x" => self.x; "y" => self.y }
}

#alias("_[_]=_")
fn Coord::set(self : Self, key : String, val : Int) -> Unit {
  match key { "x" => self.x = val; "y" => self.y = val }
}

// let c = Coord::{ x: 1, y: 2 }
// c["x"]      // 1
// c["y"] = 7  // ok
```

Implementing `_[_:_]` lets your type act as a slice source:

```mbt nocheck
struct DataView(String)
struct Data {}

#alias("_[_:_]")
fn Data::as_view(_self : Self, start? : Int = 0, end? : Int) -> DataView {
  DataView("[\{start}, \{end.unwrap_or(100)})")
}
// data[2:5]  // DataView("[2, 5)")
```

---

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
  "\{positional},\{required},\{optional},\{optional_with_default}"
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
  "\{a},\{b},\{c}"
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
