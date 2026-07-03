# MoonBit User-Defined Types & Visibility

Defining types (struct / enum / `extenum` / newtype / type alias / `derive`),
custom constructors, access control, and pattern matching. Split out of
`language.md` — traits and methods are in `traits-methods.md`, evolving a
published API (`#alias`, `#deprecated`, `#visibility`, ...) in
`refactoring.md` ("Evolving public APIs").

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
/// `trait` (default) — abstract: only the name visible outside, sealed (no outside impls)
trait MyTrait { }

///|
/// `pub trait` — readonly: methods callable outside, still sealed (no outside impls)
pub trait ReadonlyTrait { }

///|
/// `pub(open)` — trait CAN be implemented for outside packages
pub(open) trait Extendable { }
```

Trait visibility has four levels (`priv` / abstract / readonly / `pub(open)`) — see `traits-methods.md` for the full table, sealed-trait semantics, and the fact that trait *impls* carry their own independent visibility.

### `priv` fields in `pub struct`

Fields of a public struct can be individually marked `priv` — completely hidden from other packages (not readable, not matchable). A `pub struct` with any private field also loses outside construction; export a factory function instead:

```mbt nocheck
// pkg base:
pub struct Session {
  id : Int                                    // readable outside
  priv secret : String                        // invisible outside
}
pub fn Session::open(id : Int) -> Session { { id, secret: "internal" } }

// pkg consumer:
// s.id                                       // ✓ OK
// s.secret                                   // ✗ ERROR: Session has no field secret
// let s : @base.Session = { id: 2, secret: "x" }  // ✗ cannot construct outside
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


## User-defined types

### struct

```mbt check
///|
struct Point {
  x : Int
  mut y : Int                                // `mut` allows field mutation
} derive(Debug, ToJson, Eq)

///|
/// `Type::` can be omitted when the type is already known in context
let p : Point = Point::{ x: 10, y: 20 }

///|
test "mut field" {
  let q : Point = { x: 1, y: 2 }
  q.y = 3                                    // only `mut` fields can be assigned
  assert_eq(q.y, 3)
}

///|
/// pub(all) — readable AND constructible outside the package
pub(all) struct Config {
  host : String
  port : Int
} derive(Debug, Eq, ToJson, FromJson)
```

### Custom struct constructors: `fn Type::Type(...)`

A method named after its own struct becomes a constructor — `TypeName(args)` then builds the value directly (no `Type::{ ... }` literal needed at call sites). Constructors are ordinary functions: labelled/optional params, `raise`, and `async` all work:

```mbt check
///|
struct IntBox {
  value : Int
}

///|
fn IntBox::IntBox(value : Int) -> IntBox {
  { value, }
}

///|
struct Sized {
  x : Int
  y : Int
}

///|
fn Sized::Sized(x~ : Int, y? : Int = x) -> Sized {   // labelled + optional, default sees earlier params
  { x, y }
}

///|
suberror NegativeInput

///|
struct Positive {
  value : Int
}

///|
fn Positive::Positive(x : Int) -> Positive raise NegativeInput {
  guard x >= 0 else { raise NegativeInput }
  { value: x }
}

///|
test "struct constructors" {
  assert_eq(IntBox(10).value, 10)
  assert_eq(Sized(x=1).y, 1)
  let p = Positive(10) catch {
    NegativeInput => fail("unexpected")
  }
  assert_eq(p.value, 10)
}
```

Unlike enum constructors, struct constructors can NOT be used in pattern matching. `async fn Type::Type(...)` declares an async constructor (callable from async code). This is why `Type::new` is fading from core APIs — prefer `fn Type::Type(...)` for new code (`Ref(x)`, `Map(...)`, `Buffer()` follow this pattern).

### enum

```mbt check
///|
enum Tree[T] {
  Leaf(T)                                           // no trailing comma
  Node(left~ : Tree[T], T, right~ : Tree[T])        // variants can use labels
} derive(Debug, ToJson)

///|
pub enum MyResult[T, E] {
  MyOk(T)                                           // semicolon optional when newline follows
  MyErr(E)                                          // variants must start Uppercase
} derive(Debug, Eq, ToJson)

///|
pub fn Tree::sum(tree : Tree[Int]) -> Int {
  match tree {
    Leaf(x) => x                                    // no `Tree::` needed when type known
    Node(left~, x, right~) => left.sum() + x + right.sum()
  }
}
```

### Enum constructors with `mut` fields

Only **labelled** constructor fields can be `mut`. Bind the matched constructor with an as-pattern, then assign through it — this mutates in place (key for imperative structures like linked lists / BSTs with parent pointers):

```mbt check
///|
enum Chain {
  End
  Link(mut value~ : Int, mut next~ : Chain)
}

///|
test "mutable constructor fields" {
  let c = Link(value=1, next=End)
  match c {
    Link(_) as node => node.value = 5       // in-place mutation via as-binding
    End => fail("impossible")
  }
  assert_true(c is Link(value=5, ..))
}
```

### Extensible enums: `extenum`

`extenum` declares an *open* enum — more constructors can be added later with `extenum Type += { ... }`, even from other packages. Use for shared event/message/extension-point types. Regular `enum` stays closed.

```mbt nocheck
// pkg base:
pub(all) extenum LogEvent[T] {
  Info(T)
}
pub(all) extenum LogEvent[T] += {             // append in the same package
  Warning(T)
}

// pkg plugin (imports base):
pub(all) extenum @base.LogEvent[T] += {       // append from another package
  Debug(T)
}

// pkg app (imports base + plugin) — one type, constructors from both:
pub fn describe(event : @base.LogEvent[String]) -> String {
  match event {
    @base.Info(m) => "info: \{m}"
    @base.Warning(m) => "warning: \{m}"
    @plugin.Debug(m) => "debug: \{m}"
    _ => "unknown"                            // wildcard is MANDATORY — the enum is open
  }
}
```

- Constructors are qualified by the package that **defines the constructor** (`@plugin.Debug`), not the type's package; unqualified names work for current-package constructors when the expected type is known.
- Fully explicit form: `@base.LogEvent::@plugin.Debug(msg)` (type package + constructor package).
- A `match` without a wildcard arm is a partial-match error — new constructors can always appear elsewhere.

### Local types are deprecated

Declaring a `struct`/`enum` inside a function body emits `deprecated_syntax` (*"local type definition ... is deprecated. Use toplevel type definition instead"*) on current toolchains, even though older docs present it as a feature. Define types at toplevel.

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
| `Debug` | `debug_inspect()` for structural test/diagnostic output — the derivable default for your own data types. For interpolation of composed values use `\{to_repr(value)}` |
| `Show` | Specialized display strings (JSON, XML, user-facing text). Deriving it for debugging is deprecated in favor of `Debug`; write a manual `impl Show for T with output(self, logger) { ... }` only for genuine display formats |
| `Eq` | `==`, `!=` |
| `Compare` | `<`, `>`, `<=`, `>=` |
| `ToJson` | `json_inspect()` for readable test output |
| `FromJson` | JSON deserialization |
| `Hash` | Map keys |

```mbt check
///|
struct Coordinate {
  x : Int
  y : Int
} derive(Debug, Eq, ToJson)

///|
enum Status {
  Active
  Inactive
} derive(Debug, Eq, Compare)
```

**Best practice**: always derive `Debug` and `Eq` for data types; add `ToJson` if you test them with `json_inspect()`. Reserve `Show` for genuine display formats via a manual `impl`.

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

(Bitstring patterns for binary parsing live in `bytes.md`.)
