# MoonBit Toolchain Reference

Covers `moon` commands, testing, package configuration, and dependency management.

For IDE navigation (`moon ide` subcommands), see `moon-ide.md`.
Advanced build configuration (conditional compilation, link config, pre-build)
is covered in the sections below.

## Essential commands

- `moon new my_project` — create new project
- `moon run cmd/main` — run main package
- `moon run - < hello.mbt` — run code from stdin (quick experiments); also works with heredoc:
  ```bash
  moon run - <<'EOF'
  fn main {
    println("Hello, MoonBit!")
  }
  EOF
  ```
- `moon run -e "code snippet"` — run code from a command line argument:
  ```bash
  moon run -e 'fn main { println("Hello, MoonBit!") }'
  ```
- `moon build` — build project (`--target` supported)
- `moon check` — type check without building. Use REGULARLY — it is fast. (`--target` supported)
- `moon check --warn-list +unnecessary_annotation` — enable warning 73 for redundant annotations and over-qualified constructors
- `moon check --target all` — type check for all backends
- `moon info` — type check AND generate `.mbti` files. Run to see if public interfaces changed. Never edit `pkg.generated.mbti` by hand (not even whitespace cleanup) — regenerate with `moon info` and review its diff as the public-API signal.
- `moon explain` — show built-in documentation for compiler diagnostics
  - `moon explain --diagnostics` lists warning mnemonics and IDs
  - `moon explain --diagnostics 31` explains warning 31 (`unused_optional_argument`)
  - `moon explain --diagnostics unused_optional_argument` explains the same warning by mnemonic
- `moon add <package>` — add dependency
- `moon remove <package>` — remove dependency
- `moon fetch <package>[@<version>]` — download source into `.repos/` for offline reading without adding a dependency
- `moon fmt` — format code (rewrites files)
- `moon -C <dir> <subcommand>` — run in a specific directory

`moon check --output-json` can be piped through `jq` or into
`moon run --target native -e` for richer diagnostics processing. Prefer `-e`
for inline snippets; avoid old examples that use `moon run -c`.

### Build artifacts (where output lands)

Recent moon writes artifacts under `_build/` at the module root (older moon
used `target/` — check both if a path is missing). Layout:

```
_build/<target>/<mode>/build/<pkg-path>/<pkg>.<ext>
```

- `<target>`: `native`, `wasm-gc`, `js`, … — `<mode>`: `debug` (default) or `release` (`--release`)
- Native backend emits **C** you can inspect: `_build/native/release/build/main/main.c`
  (the executable sits beside it as `main.exe`). Reading this C is the reliable
  way to confirm low-level layout — e.g. a `#valtype { r:Byte; g:Byte; b:Byte }`
  compiles to a struct of three `int32_t` (12 bytes), since `Byte` fields are
  not sub-word packed; pack into a single `UInt` field for 4 bytes.
- `_build/<target>/<mode>/build/.../*.core` is the MoonBit IR; `.mi` is the
  compiled interface. `moon clean` wipes `_build/`.

### Pre-commit checklist

Always run BEFORE committing:
1. `moon fmt` — format (user expects formatted code in every commit)
2. `moon info` — regenerates `.mbti` files (user expects up-to-date `.mbti` in every commit)

Then `git status` — include any files they produce in the commit.

### Test commands

- `moon test` — run all tests (`--target` supported)
- `moon test --update` (or `-u`) — update snapshots
- `moon test -v` — verbose output with test names
- `moon test [dirname|filename]` — test specific directory or file
- `moon test [dirname|filename] --filter 'glob'` — run tests matching filter
  ```
  moon test float/float_test.mbt --filter "Float::*"
  moon test float -F "Float::*"          # shortcut
  ```
- `moon coverage analyze` — coverage analysis. Common forms:
  ```
  moon coverage analyze -- -f summary                       # per-file %
  moon coverage analyze -- -f caret -F path/to/file.mbt     # caret marks under uncovered lines
  ```
  Run `moon test` first to collect data, then drive missing branches via the public API. See `refactoring.md` for the full workflow.

## README.mbt.md generation

Output `README.mbt.md` in the package directory.

- `*.mbt.md` files treat ` ```mbt check ` code blocks specially: they are included as code AND run by `moon check` / `moon test`.
- Use ` ```mbt nocheck ` for snippets that should only be syntax-highlighted (e.g. when just referencing types).
- If you only reference types from the package, prefer `mbt nocheck`.
- Symlink `README.mbt.md` → `README.md` so systems expecting `README.md` still find content.

## Testing guide

Moved to `testing.md` — snapshot tests with the `inspect` family, black-box
defaults, docstring tests, `@test.T::snapshot` full-output snapshots, and
error handling in tests. Benchmarks and profiling: `bench-profile.md`.

## Spec-driven development

Write a `spec.mbt` file (name is conventional, not mandatory) with stub code marked as declarations:

```mbt check
///|
declare pub type Yaml

///|
declare pub fn Yaml::to_string(y : Yaml) -> String raise

///|
declare pub impl Eq for Yaml

///|
declare pub fn parse_yaml(s : String) -> Yaml raise
```

- Add `spec_easy_test.mbt`, `spec_difficult_test.mbt`, etc. — everything type-checks.
- The AI or implementer can fill in `declare` functions in different files thanks to MoonBit's package organization.
- `moon test` to verify.
- `declare` is supported for functions, methods, and types.
- `pub type Yaml` line is an intentionally opaque placeholder — the implementer chooses representation.
- Spec files can also contain normal code, not just declarations.

`declare` is the keyword form. Some templates use the `#declaration_only` attribute placed before a normal `pub fn ... { ... }` (with body `{ ... }`) — the two are equivalent surface forms of the same feature. Pick `declare` for new code unless you're following an existing project's `#declaration_only` convention.

## Package management

### Adding dependencies

```sh
moon add moonbitlang/x        # latest version
moon add moonbitlang/x@0.4.6  # specific version
```

### Updating dependencies

```sh
moon update                   # update package index
```

### Browsing third-party source (`moon fetch`)

`moon fetch <author>/<module>[@<version>]` downloads a package's source into
`.repos/<author>/<module>/<version>/` for offline reading (examples, internals,
generated `.mbti`). It does NOT add the package to `moon.mod` — use `moon add`
for that. Add `.repos/` to `.gitignore`.

```sh
moon fetch moonbitlang/async@0.18.1
```

### `moon.mod` (module metadata)

```
name = "username/hello"
version = "0.1.0"
readme = "README.mbt.md"
repository = ""
license = "Apache-2.0"
keywords = []
description = "..."
preferred_target = "native"   # optional: default backend when none is specified

import {
  "moonbitlang/x@0.4.6",
}

options(
  // source: "src", // Optional; default is "."
  "preferred-target": "native",
)
```

Use `moon add moonbitlang/x@0.4.6` and `moon remove moonbitlang/x` to manage the
`import` block instead of editing dependency versions by hand. For FFI/native
modules, set `"preferred-target": "native"` so `moon build`/`moon test`/`moon run`
default to native.

Legacy projects may still contain `moon.mod.json`; treat it as the old module
metadata format and migrate/update guidance to `moon.mod` instead of creating
new `moon.mod.json` files.

### `moon.work` (workspace manifest)

A `moon.work` file at the repository root manages **multiple modules** in one
repo (each member still has its own `moon.mod`). Most single-module projects do
not need one. The manifest is just a list of member module directories:

```
members = [
  "./mod_a",
  "./mod_b",
]
```

Manage it with `moon work` rather than hand-editing:

- `moon work init mod_a mod_b` — create `moon.work` registering the given modules.
- `moon work use mod_c` — add another module to an existing workspace.
- `moon work sync` — align workspace member versions, updating member `moon.mod`
  files when cross-member dependency versions drift.

Once `moon.work` exists, run module-spanning commands at the workspace root —
`moon check --target all`, `moon test`, `moon info`, `moon clean`. Commands that
target a single module (e.g. `moon publish`) must run inside that member, e.g.
`moon -C mod_a publish`.

**Mixed-target workspaces** (e.g. a js client + native server): bare
`moon check/test/build` falls back to wasm-gc and errors with "package(s) do
not support target backend 'wasm-gc'" — always pass `--target js|native`
explicitly, and run both targets for shared packages (protocol types etc.).
Do NOT refresh interfaces with `moon info --target X` in a multi-target
package: it rewrites `pkg.generated.mbti` to that target's specialized
surface; use default-target `moon info` and revert any target-specialized
`.mbti` diffs. Note also that `moon check` only checks the current platform's
`#cfg` branch — `--target all` covers backends, not operating systems.

### `moon.pkg` (package configuration)

Modern (preferred):
```
import {
  "username/hello/liba",
  "moonbitlang/x/encoding" @libb,
}
import {
  "username/hello/test_helpers",
} for "test"
import {
  "username/hello/internal_test_helpers",
} for "wbtest"
options(
  "is-main": true,
)
```

Use `supported_targets = "native"` or another target-set expression at top
level when the whole package only supports selected backends.

```
supported_targets = "native"
options(
  "is-main": true,
)
```

Legacy `moon.pkg.json`:
```json
{
  "is_main": true,
  "import": [
    "username/hello/liba",
    {
      "path": "moonbitlang/x/encoding",
      "alias": "libb"
    }
  ],
  "test-import": [...],
  "wbtest-import": [...]
}
```

Packages are per directory. Directories without a `moon.pkg` / `moon.pkg.json` are not recognized as packages.

### Package importing & aliases

- Import format: `"module_name/package_path"`
- Usage in code: `@alias.function()` to call imported functions
- **Default alias**: last part of path (e.g. `liba` for `username/hello/liba`)
- **Custom alias**: `import { "moonbitlang/x/encoding" @enc }` → `@enc.encode()` (unnecessary when last path segment is identical to alias)
- In `_test.mbt` / `_wbtest.mbt` files, the package being tested is auto-imported

Example:
```mbt
// After importing "username/hello/liba" in moon.pkg:
fn main {
  println(@liba.hello())
}
```

### `using` re-exports

`using` brings symbols from another package into the current one without the `@pkg.` prefix. With `pub using`, those symbols are also re-exported as part of the current package's public API:

```mbt nocheck
// In pkg_b
pub using @pkg_a { incr, type Counter, trait Tickable }
```

Now downstream callers can write `@pkg_b.incr(...)` and it resolves to `@pkg_a.incr(...)`. This is the cleanest way to:

- **Split a package gradually** — re-export from the new package, migrate callers one at a time, then move the actual definitions later (see `refactoring.md`).
- **Provide a curated facade** — collect symbols from several public packages into one public-facing one.

Without `pub`, the `using` form just brings names into local scope (no re-export). Don't conflate with the `import { ... }` block in `moon.pkg` — that adds a dependency edge, while `using` operates on already-imported packages.

#### `internal/` packages

A package at `<a>/<b>/<c>/internal/<x>` is only importable from `<a>/<b>/<c>` and its descendants. Use this for implementation support that should not leak into your public API: scanners, parsers for sub-syntax, escaping/encoding helpers, validation helpers, low-level algorithms, private helper result types.

#### Type ownership: `pub using` is for facade ergonomics, not type ownership

A package should own the public concrete types whose constructors, fields, pattern matching, and methods users are expected to use. If users think of a type as `@foo.X`, define `X` in package `foo` — or in a **non-internal public package** that `foo` re-exports. Public type ownership matters more than implementation locality.

Re-exporting a type from a non-internal public package works: MoonBit implicitly loads the owning package for method lookup, so users can name a value `@foo.X` and still call methods owned by `@bar.X`.

**Do not put public concrete types in `internal/*` and recover them via `pub using`.** External users do not get implicit method-owner loading for internal packages, so `x.method()` can fail even when `x` is typed as the facade's re-exported type. It also muddies constructors, generated interfaces, and privacy boundaries.

- Good: `pub using @parser { parse }`, `pub using @dom { type Node, to_markdown }` where `@parser` / `@dom` are public packages that own those APIs.
- Acceptable: `pub using @impl { decode_entities }` — a **value** from an internal package, if its signature exposes no internal types and it is intentionally public API.
- Avoid: `pub using @internal_impl { type X }` for a public concrete type. If `X` is public, define it in the facade or a public package; if truly internal, don't expose it.

When you need to translate internal helper results into public types, enforce public defaults, or hide internal helper types, write an explicit wrapper instead of `pub using`. Practical rule: if a public function returns `X` and users inspect, construct, match, or call methods on `X`, then `X` belongs in the facade package (or a public package it re-exports); helper packages under `internal/*` should keep their types internal or return simple helper result types.

### Standard library (moonbitlang/core)

The `moonbitlang/core` module is always available without adding it to
`moon.mod` dependencies. Ordinary core packages still need explicit `moon.pkg`
imports for package aliases such as `@utf8`, `@json`, or `@strconv`; add imports
like `"moonbitlang/core/encoding/utf8"` when the compiler reports a missing or
implicit core package.

### Creating packages

To add `fib` under the module root:
1. Create directory `./fib/`
2. Add `./fib/moon.pkg`
3. Add `.mbt` files with your code
4. Import in dependent packages:
   ```
   import {
     "username/hello/fib",
   }
   ```

### Async IO

Moved to `async.md` — runtime setup (`moon.mod`/`moon.pkg` for
`moonbitlang/async`), `with_task_group` structured concurrency, spawn closure
syntax, `async test` configuration, cancellation-safe cleanup, and pipeline
backpressure.

## Library docs lookup

**Do NOT use context7 for MoonBit packages** — MoonBit is not indexed there. Use these instead:

1. `moon ide doc <query>` — best for project-local / stdlib symbols (see `moon-ide.md`)
2. `.mbti` files — API signatures of dependencies
3. `~/.moon/registry/cache/<org>/<pkg>/<version>.zip` — extracted source for installed deps
4. mooncakes.io — browser search
5. Library GitHub repo — when on mooncakes.io

## Conditional compilation

Gate individual `.mbt` files to backends/modes. In modern `moon.pkg` DSL,
`targets` goes inside `options(...)`:

```
options(
  targets: {
    "wasm_only.mbt": ["wasm"],
    "js_only.mbt": ["js"],
    "not_js.mbt": ["not", "js"],
  },
)
```

Legacy `moon.pkg.json` equivalent:

```json
{
  "targets": {
    "wasm_only.mbt": ["wasm"],
    "js_only.mbt": ["js"],
    "debug_only.mbt": ["debug"],
    "wasm_or_js.mbt": ["wasm", "js"],
    "not_js.mbt": ["not", "js"],
    "complex.mbt": ["or", ["and", "wasm", "release"], ["and", "js", "debug"]]
  }
}
```

Available conditions:
- **Backends**: `"wasm"`, `"wasm-gc"`, `"js"`, `"native"`
- **Build modes**: `"debug"`, `"release"`
- **Logical operators**: `"and"`, `"or"`, `"not"`

## Link configuration

In modern `moon.pkg` DSL, use a top-level `link(...)` block. The native form is
well-established (see `c-ffi.md` / `c-ffi-including-sources.md`):

```
link(
  native(
    "cc-flags": "-I/path/to/include",
    "cc-link-flags": "-L/path/to/lib -lmylib",
  )
)
```

For the full per-backend option set (wasm/js exports, memory options, output
format), the legacy JSON keys below are the reference; when writing them in
`moon.pkg` DSL, verify the spelling with `moon check` before committing rather
than guessing.

Legacy `moon.pkg.json`:

```json
{
  "link": true,                          // enable linking for this package
  // OR for advanced cases:
  "link": {
    "wasm": {
      "exports": ["hello", "foo:bar"],
      "heap-start-address": 1024,
      "import-memory": {
        "module": "env",
        "name": "memory"
      },
      "export-memory-name": "memory"
    },
    "wasm-gc": {
      "exports": ["hello"],
      "use-js-builtin-string": true,
      "imported-string-constants": "_"
    },
    "js": {
      "exports": ["hello"],
      "format": "esm"                    // "esm", "cjs", or "iife"
    },
    "native": {
      "cc": "gcc",
      "cc-flags": "-O2 -DMOONBIT",
      "cc-link-flags": "-s"
    }
  }
}
```

## Warning control

In modern `moon.mod` / `moon.pkg` DSL configs, use the top-level `warnings`
field. It is translated by the toolchain to the legacy `warn-list` key.

```
warnings = "+unnecessary_annotation"  // enable warning 73
warnings = "+73"                      // equivalent
warnings = "-2-29"                    // disable unused variable and unused package
```

Use the same values on the command line with `--warn-list`:

```sh
moon check --warn-list +unnecessary_annotation
moon check --warn-list +73
```

In legacy JSON configs (`moon.mod.json` or `moon.pkg.json`), the key is still
`warn-list`:

```json
{
  "warn-list": "-2-29"                   // disable unused variable (2) & unused package (29)
}
```

Common warning numbers:
- `1` — unused function
- `2` — unused variable
- `11` — partial pattern matching
- `12` — unreachable code
- `29` — unused package
- `73` / `unnecessary_annotation` — redundant annotations and over-qualified constructors

Run `moonc build-package -warn-help` to see all available warnings.

## Pre-build commands

Embed external files as MoonBit code. (Shown in legacy `moon.pkg.json` form —
if the package uses the `moon.pkg` DSL, verify the current `pre-build` DSL
spelling with `moon check` rather than guessing.)

```json
{
  "pre-build": [
    {
      "input": "data.txt",
      "output": "embedded.mbt",
      "command": ":embed -i $input -o $output --name data --text"
    }
  ]
}
```

Generated code example:

```mbt check
///|
let data : String =
  #|hello,
  #|world
  #|
```

## More

- `moon-ide.md` — `moon ide` subcommand deep reference (goto-definition, find-references, tags, query syntax)
