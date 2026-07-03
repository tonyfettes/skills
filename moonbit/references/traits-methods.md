# MoonBit Methods, Traits, and Operators

Method declaration, dot-syntax resolution, trait definition and `impl`, `Self`, default trait methods (`= _`), trait inheritance, trait visibility, trait objects (`&Trait`), `#must_implement_one`, local methods on foreign types, operator overloading, and indexing operators via `#alias`. Split out of `language.md`.

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

### Method overloading and `Trait::method(x)` direct calls

`Type::method` names live in per-type namespaces, so different types can define same-named methods (unlike free functions). Trait methods can also be called fully qualified — MoonBit infers `Self` and checks the constraint:

```mbt check
///|
struct A1 {
  x : Int
}

///|
struct A2 {
  y : Int
}

///|
fn A1::default() -> A1 {
  { x: 0 }
}

///|
fn A2::default() -> A2 {
  { y: 0 }                                    // same name, different namespace — OK
}

///|
test "overloading and direct trait calls" {
  assert_eq(A1::default().x, 0)
  assert_eq(A2::default().y, 0)
  assert_eq(Show::to_string(42), "42")        // Trait::method — Self inferred as Int
  assert_eq(Compare::compare(1.0, 2.5), -1)
}
```

### Dot syntax resolution rules

When you write `x.m(...)`:

1. A **regular method** (`fn T::m`) always wins over a trait `impl` with the same name.
2. A trait `impl` is dot-callable **only if it lives in the package of the self type** — from other packages, call `Trait::m(x)` or go through a generic with a trait bound.
3. If multiple traits provide same-named dot-callable methods, it's an **ambiguity error** — qualify with `Trait::m(x)`.

```mbt check
///|
trait Speaks {
  say(Self) -> String
}

///|
struct Robot {}

///|
impl Speaks for Robot with say(_) {
  "trait impl"
}

///|
fn Robot::say(_self : Robot) -> String {
  "regular method"
}

///|
test "dot resolution" {
  let r = Robot::{  }
  assert_eq(r.say(), "regular method")        // rule 1: regular method wins
  assert_eq(Speaks::say(r), "trait impl")     // qualified call reaches the impl
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

**Empty traits are NOT auto-implemented** (despite older docs claiming otherwise) — `fn[T : Marker] f(x : T)` rejects any type without an explicit `impl Marker for Type`. Write the (empty) `impl` for each type you want in.

### `#must_implement_one`

When every method has a default, `impl Trait for Type` alone would inherit them all — `#must_implement_one` forces implementers to explicitly provide at least one method (or one from a named group). Multiple `#must_implement_one` attributes = multiple groups, each must be satisfied:

```mbt check
///|
/// Classic mutual-defaults trait: each default is defined via the other,
/// so an implementer must break the cycle by providing one explicitly.
#must_implement_one
pub(open) trait Measurable {
  size(Self) -> Int = _
  is_empty(Self) -> Bool = _
}

///|
impl Measurable with size(self) {
  if self.is_empty() { 0 } else { 1 }
}

///|
impl Measurable with is_empty(self) {
  self.size() == 0
}

///|
struct Payload {}

///|
impl Measurable for Payload with size(_) {
  4                                           // satisfies the requirement
}
// impl Measurable for Payload               // ✗ ERROR [4206]: requires explicit
//                                           //   implementation for at least one method
```

`#must_implement_one(f, g)` restricts the requirement to the listed methods: implementing only some *other* method still errors with *"requires explicit implementation for at least one of f, g"*.

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

### Trait visibility: four levels

| Declaration | Name visible outside | Methods callable outside | Implementable outside |
|---|---|---|---|
| `priv trait` | no | no | no |
| `trait` (default = **abstract**) | yes (name only) | no | no — **sealed** |
| `pub trait` (**readonly**) | yes | yes | no — **sealed** |
| `pub(open) trait` | yes | yes | yes |

- Abstract and readonly traits are **sealed**: `impl @pkg.Trait for MyType` outside the defining package is a compile error (`[4145]`). The author can rely on the closed set of impls.
- An abstract trait still works outside through `pub fn[T : Trait]` functions exported by the defining package — callers just can't see or add methods.
- **Trait impls have their own visibility, independent of the trait**: a non-`pub` `impl Trait for Type` is invisible outside — other packages get *"Type does not implement trait ... no `impl` is defined"* (`[4018]`). Write `pub impl Trait for Type with ...` when the conformance is part of your API.
- Coherence: only the package of the *type* or the package of the *trait* may write `impl @pkg1.Trait for @pkg2.Type`.

```mbt nocheck
// pkg base:
pub trait Sealed { key(Self) -> Int }         // readonly: callable, not implementable outside
pub impl Sealed for Int with key(self) { self }   // pub impl — visible to consumers
pub fn[T : Sealed] use_sealed(x : T) -> Int { x.key() }

// pkg consumer:
// @base.use_sealed(42)                       // ✓ OK — pub impl for Int is visible
// impl @base.Sealed for MyType with key(_) { 0 }  // ✗ ERROR [4145]: sealed
```

### Trait objects (`&Trait`)

Runtime polymorphism: `t as &I` boxes a value with its `I` methods into an object, erasing the concrete type — so values of different types can share one data structure. When the expected type is already `&I`, the `as &I` can be omitted:

```mbt check
///|
pub(open) trait Animal {
  speak(Self) -> String
}

///|
struct Duck(String)

///|
struct Fox(String)

///|
impl Animal for Duck with speak(self) {
  "\{self.0}: quack!"
}

///|
impl Animal for Fox with speak(_self) {
  "What does the fox say?"
}

///|
/// Methods can be defined on the trait object type itself, like on any struct/enum
fn &Animal::speak_twice(self : &Animal) -> String {
  self.speak() + " " + self.speak()
}

///|
test "trait objects" {
  let duck : Duck = Duck("donald")
  let fox : Fox = Fox("nick")
  let animals : Array[&Animal] = [duck as &Animal, fox]  // fox coerced — `as &Animal` optional here
  assert_eq(animals[0].speak(), "donald: quack!")
  assert_eq(animals[1].speak_twice(), "What does the fox say? What does the fox say?")
}
```

**Object safety** — a trait can only be made into `&Trait` when every method:

- takes `Self` as the **first** parameter, and
- mentions `Self` **exactly once** (i.e. only that first parameter — no `Self` returns, no second `Self` argument).

So traits with constructors (`empty() -> Self`) or binary methods (`op_equal(Self, Self) -> Bool`) are not object-safe — use generics with trait bounds (`fn[T : Trait]`) for those instead. Generic bounds are static dispatch (no boxing); reach for `&Trait` only when you genuinely need heterogeneous collections or runtime substitution.

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
} derive(Debug)

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
