# `moon ide` Reference

`moon ide` subcommands provide semantic navigation, API discovery, and refactoring for MoonBit projects. **Always prefer `moon ide` over manual `grep` / file searching** — the IDE tools understand MoonBit semantics, save tokens, and are more precise (grep picks up comments and unrelated matches).

## Subcommand overview

| Subcommand | Purpose |
|---|---|
| `moon ide doc <query>` | API discovery — find functions / types / methods by name |
| `moon ide outline [dir\|file]` | Top-level symbols in a package or file |
| `moon ide find-references <sym>` | All usages of a symbol |
| `moon ide peek-def <sym> [--loc ...]` | Inline definition context |
| `moon ide hover <sym> --loc ...` | Type signature + docstring at a location |
| `moon ide goto-definition -query ... [-tags ...]` | Locate symbol definition with rich filtering |
| `moon ide rename <sym> <new_name> [--loc ...]` | Semantic project-wide rename |
| `moon ide analyze [path]` | Inspect public API usage when planning safe refactors |

## `moon ide doc` — API discovery

Specialized query syntax for symbol lookup.

- **Empty query**: `moon ide doc ''`
  - In a module: all available packages (including deps and `moonbitlang/core`)
  - In a package: all symbols in current package
  - Outside a package: all available packages
- **Function/value**: `moon ide doc "[@pkg.]value_or_function_name"`
- **Type**: `moon ide doc "[@pkg.]Type_name"` (builtin types don't need a package prefix)
- **Method/field**: `moon ide doc "[@pkg.]Type_name::method_or_field_name"`
- **Package exploration**: `moon ide doc "@pkg"` — list all exported symbols
  - `moon ide doc "@json"` — the `@json` package
  - `moon ide doc "@encoding/utf8"` — nested package
- **Globbing**: `moon ide doc "String::*rev*"` — all methods with `rev` in name

### Examples

```bash
# String methods in the standard library
$ moon ide doc "String"
type String
  pub fn String::add(String, String) -> String
  # ... more ...

# List all symbols in @buffer
$ moon ide doc "@buffer"
moonbitlang/core/buffer
fn from_array(ArrayView[Byte]) -> Buffer
# ... omitted ...

# Specific function
$ moon ide doc "@buffer.new"
package "moonbitlang/core/buffer"
pub fn new(size_hint? : Int) -> Buffer

# Globbing
$ moon ide doc "String::*rev*"
pub fn String::rev(String) -> String
pub fn String::rev_find(String, StringView) -> Int?
```

## `moon ide rename` — semantic rename

```
moon ide rename <sym> <new_name> [--loc filename:line:col]
```

When names are ambiguous, pass `--loc` to disambiguate. The command emits a patch you can apply.

Example: `Can you rename compute_sum to calculate_sum?`

```
$ moon ide rename compute_sum calculate_sum --loc math_utils.mbt:2

*** Begin Patch
*** Update File: cmd/main/main.mbt
@@
-  println(@math_utils.compute_sum(1, 2))
+  println(@math_utils.calculate_sum(1, 2))
*** Update File: math_utils.mbt
@@
-pub fn compute_sum(a: Int, b: Int) -> Int {
+pub fn calculate_sum(a: Int, b: Int) -> Int {
*** Update File: math_utils_test.mbt
@@
-  inspect(@math_utils.compute_sum(1, 2))
+  inspect(@math_utils.calculate_sum(1, 2))
*** End Patch
```

## `moon ide hover` — signature + docs at location

```
moon ide hover <sym> --loc filename:line:col
```

Example: "What is the signature and docstring of `filter` at line 14 of hover.mbt?"

```
$ moon ide hover filter --loc hover.mbt:14
test {
  let a: Array[Int] = [1]
  inspect(a.filter((x) => {x > 1}))
            ^^^^^^
            fn[T] Array::filter(self : Array[T], f : (T) -> Bool raise?) -> Array[T] raise?
            ---
            Creates a new array containing all elements from the input array that satisfy
            ... omitted ...
}
```

## `moon ide peek-def` — definition context

Better than `grep` (semantic, not textual):

```
moon ide peek-def <sym> [--loc filename:line:col]
```

Example: "Is `Parser::read_u32_leb128` implemented correctly?"

```
$ moon ide peek-def Parser::read_u32_leb128
file src/parse.mbt
L45:|///|
L46:|fn Parser::read_u32_leb128(self : Parser) -> UInt raise ParseError {
L47:|  ...
```

Follow up — see the `Parser` struct definition:

```
$ moon ide peek-def Parser --loc src/parse.mbt:46:4
Definition found at file src/parse.mbt
  | ///|
2 | priv struct Parser {
  |             ^^^^^^
  |   bytes : Bytes
  |   mut pos : Int
  | }
```

For `--loc`, the line number must be precise; the column can be approximate (the positional `<sym>` narrows it down).

If the symbol is a toplevel name, you can omit `--loc`:

```
$ moon ide peek-def String::rev
Found 1 symbols matching 'String::rev':
`pub fn String::rev` in package moonbitlang/core/builtin at ...:1039-1044
```

## `moon ide outline` & `find-references`

```
moon ide outline .                  # outline current package, per-file headers
moon ide outline parser.mbt         # outline a single file
moon ide find-references <sym>      # usages across the current module
```

Use outline to quickly inventory a package or find the right file before `goto-definition`.

```
$ moon ide outline .
spec.mbt:
 L003 | pub(all) enum CStandard {
        ...
 L013 | pub(all) struct Position {
        ...

$ moon ide find-references TranslationUnit
```

## `moon ide goto-definition` — richer query

Two-part query system: symbol name (with optional `@pkg` prefix) + tag filters.

### Symbol name queries (`-query`)

Fuzzy search with package filtering:

```bash
moon ide goto-definition -query 'symbol'                                    # any symbol
moon ide goto-definition -query 'Type::method'                              # methods of a type
moon ide goto-definition -query 'Trait for Type with method'                # trait method impl
moon ide goto-definition -query '@moonbitlang/x encode'                     # scope to a package
moon ide goto-definition -query '@a/mod/pkg1 @a/mod/pkg2 helper'            # pkg1 OR pkg2
moon ide goto-definition -query '@username/mymodule/mypkg helper'           # nested package
```

**Supported symbols**: functions, constants, let bindings, types, structs, enums, traits. **Package filtering**: `@pkg` prefixes create OR conditions.

### Tag filters (`-tags`)

Pre-filter by symbol characteristics before name matching.

**Visibility:** `pub`, `pub all`, `pub open`, `priv`

**Symbol type:** `type`, `error`, `enum`, `struct`, `alias`, `let`, `const`, `fn`, `trait`, `impl`, `test`

Combine with `|` (OR) and parentheses:

```bash
moon ide goto-definition -tags 'pub fn'          -query 'my_func'
moon ide goto-definition -tags 'fn | const'      -query 'helper'
moon ide goto-definition -tags 'pub (fn | const)' -query 'api'
moon ide goto-definition -tags 'pub (type | trait)' -query 'MyType'
```

### Practical examples

```bash
# Public function definition
moon ide goto-definition -tags 'pub fn' -query 'maximum'

# References to a struct
moon ide find-references -tags 'struct' -query 'Rectangle'

# Trait implementations
moon ide goto-definition -tags 'impl' -query 'Show for MyType'

# Error types in a package
moon ide goto-definition -tags 'error' -query '@mymodule/parser ParseError'

# Across multiple packages
moon ide goto-definition -query '@moonbitlang/x @moonbitlang/core encode'

# Package + tags combined
moon ide goto-definition -tags 'pub fn' -query '@username/myapp helper'
```

### Query processing order

1. Filter by `-tags`
2. Extract `@pkg` prefixes from `-query` for scope
3. Fuzzy match remaining symbols by name
4. Return top 3 matches with locations

**Best practice**: start with `-tags` to reduce noise, then add `@pkg` in `-query` to scope precisely.
