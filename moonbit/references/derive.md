# `derive(...)` Reference

Configuring auto-derived traits. For the bare list of derivable traits, see `types.md`. This file covers the configuration arguments — especially for `FromJson` / `ToJson`, where the defaults often aren't what you want.

## Quick rules

- A trait `T` can be derived only if every field used in the type already implements `T`.
- Always derive `Debug` and `Eq` on data types; add `ToJson` if you `json_inspect` them in tests. Deriving `Show` for debugging is deprecated — reserve `Show` for genuine display formats via a manual `impl Show for T with output(...)`.
- For `FromJson` / `ToJson` arguments more advanced than `style`, `rename_fields`, and per-field `rename`, **manually implement the trait** — many older args (`repr`, `case_repr`, `default`, `rename_all`) have been deprecated.
- On a non-`priv` type every derive warns `implicit_impl_as_method` (0079) until you add `extend` lines — see below.

## Derives and `extend` lines (warning 0079)

Derived impls are `pub`, and the compiler still attaches their methods to the
type as regular methods (`x.to_json()`, `T::default()`) — a deprecated implicit
promotion that warns on moonc ≥ 0.10.14 (verified on 0.10.16, core does the
same in its `extends.mbt` files). Say explicitly which methods stay:

```mbt check
///|
pub(all) enum Level {
  Low
  High
} derive(Debug, Eq, ToJson)

///|
pub extend Level with ToJson::{to_json} // keep `level.to_json()`

///|
#deprecated
pub extend Level with Eq::{equal, not_equal} // acknowledge; `==` / `!=` still work

///|
#deprecated
pub extend Level with @debug.Debug::{to_repr} // `debug_inspect` / `Repr(x)` still work
```

- Operators, `debug_inspect`, `json_inspect`, `Repr(x)` and `Trait::method(x)`
  go through the trait and need no method; extend only what you call with dot
  syntax. A non-`pub` `extend` does not silence the warning.
- `priv` types never warn — internal-only types should be `priv` anyway
  (`missing_priv`, 0004).
- The warning text lists each trait's method set: `Eq::{equal, not_equal}`,
  `Compare::{compare, op_lt, op_le, op_gt, op_ge}`, `Hash::{hash, hash_combine}`,
  `Default::{default}`, `Show::{output, to_string}`, `FromJson::{from_json}`
  (`@json.FromJson` outside the json package). Naming `@debug.Debug` in an
  `extend` line needs `moonbitlang/core/debug` imported; `derive(Debug)` alone
  does not.

## Derivable traits

| Trait | Enables |
|---|---|
| `Debug` | `debug_inspect()`, `\{Repr(value)}` interpolation (`to_repr` is its deprecated old name) — the derivable default for data types |
| `Show` | `to_string()`, string interpolation `\{value}` — manual `impl` for display formats; deriving for debugging is deprecated |
| `Eq` | `==`, `!=` |
| `Compare` | `<`, `>`, `<=`, `>=` (orders enums by definition order) |
| `Default` | `Default::default()` (`T::default()` needs `pub extend T with Default::{default}`) |
| `Hash` | `Map` / `HashSet` keys |
| `Arbitrary` | property testing (`@quickcheck`); write as `derive(@quickcheck.Arbitrary)` |
| `Shrink` | counterexample shrinking (`derive(@quickcheck.Shrink)`) — in-place field shrinking only, see `testing.md` "Property tests" |
| `ToJson` | `json_inspect`, `@json.to_json(x)` (`x.to_json()` needs an `extend` line) |
| `FromJson` | `@json.from_json` — the package must import `moonbitlang/core/json` even for the derive alone (else `core_package_not_imported`, 0071) |

### `Default` requirements

- **Struct**: every field's type must derive `Default`.
- **Enum**: exactly one constant (no-payload) variant — ambiguous if multiple, undefined if none.

```mbt nocheck
enum DeriveDefaultEnum {
  Case1(Int)
  Case2(label~ : String)
  Case3                              // chosen as default
} derive(Default, Eq, Debug)
```

## `FromJson` / `ToJson`

### Enum encoding styles

You **must** pick one with `style="legacy"` or `style="flat"`. Considering:

```mbt nocheck
enum E {
  One
  Uniform(Int)
  Axes(x~: Int, y~: Int)
}
```

| Variant | `style="legacy"` | `style="flat"` |
|---|---|---|
| `E::One` | `{"$tag": "One"}` | `"One"` |
| `E::Uniform(2)` | `{"$tag": "Uniform", "0": 2}` | `["Uniform", 2]` |
| `E::Axes(x=-1, y=1)` | `{"$tag": "Axes", "x": -1, "y": 1}` | `["Axes", -1, 1]` |

Pick `flat` for compact output; pick `legacy` when consumers expect tagged objects.

### `Option[T]` direct-field rule

Inside a struct field, `Option[T]` is encoded as `T | undefined` only when it's a **direct** struct field. In nested positions (tuples, nested options, collections), it falls back to `[T] | null`.

```mbt nocheck
struct A {
  x : Int?         // direct field      → Some(1) ⇒ 1, None ⇒ omitted
  y : Int??        // nested            → Some(None) ⇒ null, Some(Some(1)) ⇒ [1]
  z : (Int?, Int??)// nested            → uses [T] | null encoding
} derive(ToJson)
```

This is why `Some(None)` and `None` would otherwise be indistinguishable for `Option[Option[T]]`.

### Container arguments

```mbt nocheck
struct S { my_long_name : Int } derive(ToJson(rename_fields="PascalCase"))
// → { "MyLongName": 0 }
```

- **`rename_fields = "..."`** — applies to struct fields and enum case payloads. Available formats: `lowercase`, `UPPERCASE`, `camelCase`, `PascalCase`, `snake_case`, `SCREAMING_SNAKE_CASE`, `kebab-case`, `SCREAMING-KEBAB-CASE`. Assumes input fields are `snake_case`.
- **`rename_cases = "..."`** (enum only) — same formats; assumes input variants are `PascalCase`.
- **`fields(x(...), y(...))`** (struct only) — per-field overrides.
- **`cases(A(...), B(...))`** (enum only) — per-case overrides.

### Per-field / per-case arguments

- **`rename = "..."`** — overrides container-wide `rename_fields` / `rename_cases`. Cannot rename positional fields.
- Combine with `fields(...)` to scope: `derive(ToJson(fields(x(rename="renamedX"))))`.

```mbt nocheck
struct JsonTest3 {
  x : Int
  y : Int
} derive (
  FromJson(fields(x(rename="renamedX"))),
  ToJson(fields(x(rename="renamedX"))),
)
// → { "renamedX": 123, "y": 456 }
```

## When to skip `derive` and implement manually

- You need custom keys, conditional fields, computed fields, or version migration.
- You need a layout that's neither `legacy` nor `flat` (e.g. internally-tagged objects).
- You need anything from the deprecated argument list (`repr`, `case_repr`, `default`, `rename_all`).

`impl ToJson for MyType with to_json(self) { ... }` and `impl FromJson for MyType with from_json(json) { ... }` are usually clearer than fighting the derive macro.
