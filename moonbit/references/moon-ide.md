# `moon ide` Reference

`moon ide` subcommands provide semantic navigation, API discovery, and refactoring for MoonBit projects. **Always prefer `moon ide` over manual `grep` / file searching** — the IDE tools understand MoonBit semantics, save tokens, and are more precise (grep picks up comments and unrelated matches).

This file reflects **moon 0.1.20260803** (moonc v0.10.6). Notable changes from
older toolchains: `moon ide goto-definition` (with its `-tags`/`-query`
filters) was **removed** — use `peek-def` for exact lookup or
`workspace-symbols` for fuzzy search; `workspace-symbols` is **new**; `rename`
gained `--apply`; `hover`/`peek-def`/`find-references`/`workspace-symbols`
gained `--json`.

Common flags on every subcommand: `--no-check` (skip the implicit
`moon check` that refreshes the build graph first) and `--target <backend>`
(pass through to that check). Run the commands from inside the module — a
`moon.work` workspace root also works and covers all member modules.

## Subcommand overview

| Subcommand | Purpose |
|---|---|
| `moon ide doc <query>` | API discovery — find functions / types / methods by name (module + deps + core) |
| `moon ide workspace-symbols <query> [--json]` | Fuzzy-search top-level symbols across the module/workspace, with locations |
| `moon ide outline [dir\|file]` | Top-level symbols in a package or file, with line numbers |
| `moon ide peek-def <sym> [--loc ...] [--json]` | Resolve a definition; inline source context |
| `moon ide find-references <sym> [--loc ...] [--json]` | All usages of a symbol |
| `moon ide hover [<token>] --loc ... [--output-json]` | Type signature + docstring at a location |
| `moon ide rename <sym> <new> [--loc ...] [--apply]` | Semantic project-wide rename |
| `moon ide analyze [pkg-dir...]` | Public API usage counts across dependents |
| `moon ide gen-symbols` | Write `./symbols.jsonl` for the current package (tooling/tests only — pollutes cwd) |

## `moon ide doc` — API discovery

Specialized query syntax for symbol lookup. Searches the current module, its
dependencies, `moonbitlang/core`, and registry symbol indexes
(`--no-registry` excludes registry packages). Output is signatures and docs —
no source locations; use `workspace-symbols` or `peek-def` when you need the
location.

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

# Specific function
$ moon ide doc "@buffer.new"
package "moonbitlang/core/buffer"
pub fn new(size_hint? : Int) -> Buffer

# Globbing
$ moon ide doc "String::*rev*"
pub fn String::rev(String) -> String
pub fn String::rev_find(String, StringView) -> Int?
```

## `moon ide workspace-symbols` — fuzzy symbol search

```
moon ide workspace-symbols <query> [--json]
```

Searches top-level symbols in the current module or workspace with the same
fuzzy matching as the LSP `workspace/symbol` request. An empty query (`''`)
lists every symbol. Private symbols are included.

```bash
$ moon ide workspace-symbols 'flip' --json
[{"name":"pub fn Point::flip","kind":"Function",
  "location":{"path":"/w/src/kinds.mbt","range":"19:1-21:2"}}]
```

JSON row shape: `name` is the declaration head (`pub fn Point::flip`,
`const MaxSize`, `pub enum Color::Green`) — take the last space-separated
token for the bare name. `kind` is an LSP `SymbolKind` *name*: `Function`,
`Variable` (const/let), `Enum` (also for `suberror`), `EnumMember`,
`Object` (struct), `Interface` (trait). `range` is 1-based
`line:col-line:col` spanning the whole declaration. No match → `[]`, exit 0.

## `moon ide hover` — signature + docs at location

```
moon ide hover <token> --loc <path:line[:col]>
moon ide hover --loc <path:line:col>            # token optional with full loc
```

`--loc` is 1-based; the line is required, and `<token>` only helps find the
column on that line — with file, line, AND column given it may be omitted.
Plain output is highlighted source context; `--json` / `--output-json` prints
one object instead:

```bash
$ moon ide hover --loc src/lib.mbt:10:3 --output-json
{"range":"10:3-10:6","contents":["```moonbit\nfn add(a : Int, b : Int) -> Int\n```","\n Adds two integers together."]}
```

`contents` is markdown sections (signature block, then docstring); `range` is
the hovered token's 1-based span. Nothing at the position → non-zero exit
with a message, no JSON.

## `moon ide peek-def` — definition context

Better than `grep` (semantic, not textual):

```
moon ide peek-def <symbol>                        # semantic query, module/workspace-wide
moon ide peek-def <token> --loc <path[:line[:col]]>
moon ide peek-def --loc <path:line:col> [--json]
```

Accepted symbol forms: `foo`, `@pkg.foo`, `Type::member`,
`@pkg.Type::member`, `Trait::method for Type`. With file-only `--loc` the
lookup is restricted to that file; with line/col the symbol resolves from the
exact position (use for locals, shadowed names, ambiguity). The line must be
precise; the column can be approximate when `<token>` narrows it down.

```bash
$ moon ide peek-def bare_symbol_name
Found 1 symbols matching 'bare_symbol_name':

`fn bare_symbol_name` in package my/mod/pkg at /w/src/names.mbt:661-670
661 | ///|
    | /// The bare symbol name out of a declaration head ...
    | fn bare_symbol_name(head : String) -> String? {

$ moon ide peek-def bare_symbol_name --json
[{"path":"/w/src/names.mbt","range":"665:4-665:20"}]
```

## `moon ide find-references`

```
moon ide find-references <symbol>                 # semantic query, module/workspace-wide
moon ide find-references <token> --loc <path[:line[:col]]>
moon ide find-references --loc <path:line:col> [--json]
```

Same symbol forms and `--loc` resolution rules as `peek-def`. Output: the
resolved definition followed by all reference locations; `--json` prints them
as an array.

## `moon ide rename` — semantic rename

```
moon ide rename <symbol> <new-name> [--loc <path[:line[:col]]>] [--apply]
```

Without `--apply`, prints a patch-style edit list for review; with `--apply`,
rewrites the files and prints a summary. When names are ambiguous, pass
`--loc` to disambiguate.

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
*** End Patch
```

## `moon ide outline`

```
moon ide outline .                  # outline current package, per-file headers
moon ide outline parser.mbt         # outline a single file
moon ide outline path/to/pkg        # outline another package directory
```

Prints top-level declarations with line numbers, per file. Use it to quickly
inventory a package or find the right file before `peek-def`.

```
$ moon ide outline desktop/internal/moonbit
toolchain_paths.mbt:
  2 |const MoonbitBundleStampFile : String = ".openseek-moonbit-bundle-version"
    |...
  8 |fn moonbit_toolchain_dir(base : @path.Path, name : String) -> @path.Path {
    |...
```

## `moon ide analyze`

```
moon ide analyze [<package-dir>...]
```

Reports how public APIs are used by dependents — exported items annotated
with usage counts. With no paths, analyzes all local packages in the module
or workspace. Use it when planning safe refactors and API shrinkage.

## `moon ide gen-symbols`

Writes all symbols of the **current package** to `./symbols.jsonl` (with
declaration and name ranges). Mainly for tooling and tests; it prints nothing
to stdout and drops a file into the package directory — prefer
`workspace-symbols` for interactive lookup.
