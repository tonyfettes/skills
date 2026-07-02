# MoonBit Methods, Traits, and Operators

Method declaration, trait definition and `impl`, `Self`, default trait methods (`= _`), trait inheritance, local methods on foreign types, operator overloading, and indexing operators via `#alias`. Split out of `language.md`.

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
