# Evolving Public APIs

Shims and attributes for changing a published API without breaking callers:
renaming (`#alias`), fn↔method moves (`#as_free_fn`), deprecation
(`#deprecated`), parameter changes (`#label_migration`), visibility tightening
(`#visibility`), and usage warnings (`#alert`). Needed whenever a package has
external consumers — during feature work and releases, not just refactors.
Workflow-level refactoring guidance is in `refactoring.md`.

## Migration shims

### Free function ↔ method: `#as_free_fn`

When you want to convert a free function `foo(x)` into a method `Bar::foo(self)`, place `#as_free_fn(foo, deprecated="Use Bar::foo")` on the new method. The compiler emits a deprecated free function `foo` that forwards to the method. Old callers keep working with a warning; you migrate them one at a time guided by the warnings.

```mbt nocheck
#as_free_fn(reader_next, deprecated="Use Reader::next instead")
fn Reader::next(self : Reader) -> Char? { ... }
// Old: reader_next(r)         — still compiles, emits deprecation warning
// New: r.next()
```

The reverse direction — exposing a method as a free function intentionally — uses the same attribute without `deprecated`:

```mbt nocheck
#as_free_fn(m)                            // public method exposed as `m()`
#as_free_fn(n, visibility="pub")          // also pick a visibility
fn List::f() -> Bool { true }
```

### Renaming an existing API: `#alias`

`#alias(old_name, deprecated)` adds an alternate (deprecated) name for an existing function. Use it when **renaming**, not when changing function-vs-method shape:

```mbt nocheck
#alias(compute_sum, deprecated="Use calculate_sum")
pub fn calculate_sum(a : Int, b : Int) -> Int { a + b }
```

Strip the alias once `find-references compute_sum` returns nothing.

### `#deprecated` for shape-preserving deprecation

If you don't need a forwarding shim — just want to discourage callers — `#deprecated("message")` annotates an existing item:

```mbt nocheck
#deprecated("Will be removed in 0.5; use BarV2")
pub fn old_api() -> Unit { ... }
```

Add `skip_current_package=true` when intra-package callers are intentional and don't need warnings.

### Evolving parameters: `#label_migration`

Changes a function's *parameter shape* without breaking callers — the shim
lives on the parameter, not on a duplicate function. Three forms (one
attribute per parameter; stack several on one function):

```mbt nocheck
#label_migration(x, fill=true, msg="x will become required")   // optional → required:
#label_migration(y, fill=false, msg="y will be removed")       //   warns on call sites that OMIT x
fn evolve(x? : Int = 0, y? : Int = 1) -> Int { ... }           // fill=false: warns on sites that PASS y

#label_migration(count, allow_positional=true)   // positional → labelled:
fn take(count~ : Int) -> Int { ... }             //   take(3) still compiles, warns to use count=3

#label_migration(size, alias=len, msg="len is renamed to size") // rename a label:
fn resize(size~ : Int) -> Int { ... }            //   resize(len=4) works; warns only if msg given
```

Verified: the warnings surface as `deprecated`-class warnings at exactly the
call sites that will break, so `moon check` output is the migration worklist.
Omitting `msg` on the `alias` form makes the old label a silent, permanent
alias — include `msg` when you intend to remove it.

### Announcing visibility tightening: `#visibility`

When a `pub(all)` type is headed for `readonly` or `abstract`, warn users
*before* the break. Usages that the future visibility would invalidate get an
`alert_visibility` warning now:

```mbt nocheck
#visibility(change_to="readonly", "Point will be readonly in the future.")
pub(all) struct Point {
  x : Int
  y : Int
}
// Downstream: Point::{ x: 1, y: 2 }  → warns (construction breaks under readonly)
//             p.x                    → no warning (reads stay legal)
```

`change_to="readonly"` flags construction and field mutation;
`change_to="abstract"` additionally flags pattern matching and field access.
Pass the message positionally — the `message=` keyword form crashed the
compiler on moon 0.1.20260629.

### Warning on use: `#alert(category, "msg")`

Attaches a warning to an API that fires at every call site — for `unsafe`,
`experimental`, or project-specific categories, without implying removal the
way `#deprecated` does:

```mbt nocheck
#alert(experimental, "parser API may change in 0.x")
pub fn parse_v2(s : String) -> Ast { ... }
// call sites warn: Warning (alert_experimental): parser API may change in 0.x
```

Control per category via the package warn-list: warning name is
`alert_<category>`, and `alert` addresses all categories (e.g.
`warnings = "@alert-alert_unsafe"` in `moon.pkg` = all alerts fatal except
`unsafe` disabled). Gotcha: `alert_unsafe` is **off by default** — an
`#alert(unsafe, ...)` is silent until the consumer opts in; pick another
category if you need the warning visible out of the box.

