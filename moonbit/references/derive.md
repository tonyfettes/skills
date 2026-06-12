# `derive(...)` Reference

Configuring auto-derived traits. For the bare list of derivable traits, see `language.md`. This file covers the configuration arguments — especially for `FromJson` / `ToJson`, where the defaults often aren't what you want.

## Quick rules

- A trait `T` can be derived only if every field used in the type already implements `T`.
- Always derive `Show` and `Eq` on data types; add `ToJson` if you `@json.inspect` them in tests.
- For `FromJson` / `ToJson` arguments more advanced than `style`, `rename_fields`, and per-field `rename`, **manually implement the trait** — many older args (`repr`, `case_repr`, `default`, `rename_all`) have been deprecated.

## Derivable traits

| Trait | Enables |
|---|---|
| `Show` | `to_string()`, string interpolation `\{value}` |
| `Eq` | `==`, `!=` |
| `Compare` | `<`, `>`, `<=`, `>=` (orders enums by definition order) |
| `Default` | `T::default()` |
| `Hash` | `Map` / `HashSet` keys |
| `Arbitrary` | property testing (`@quickcheck`) |
| `ToJson` | `@json.inspect`, `to_json()` |
| `FromJson` | `@json.from_json` |

### `Default` requirements

- **Struct**: every field's type must derive `Default`.
- **Enum**: exactly one constant (no-payload) variant — ambiguous if multiple, undefined if none.

```mbt nocheck
enum DeriveDefaultEnum {
  Case1(Int)
  Case2(label~ : String)
  Case3                              // chosen as default
} derive(Default, Eq, Show)
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
