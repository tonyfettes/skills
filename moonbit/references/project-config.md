# MoonBit Project Configuration

Module/package/workspace configuration: `moon.mod`, `moon.pkg`, `moon.work`,
dependencies, imports & aliases, `using` re-exports, conditional compilation,
link configuration, warning control, and pre-build commands.

Day-to-day `moon` commands and the dev/test workflow are in `toolchain.md`.

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

### Finding packages

```sh
moon search <keyword> [--json]           # registry search (modules + package summaries)
moon view user/module[@version]          # registry metadata; --versions lists every release
moon view <username>                     # a user's published modules
```

`moon view --versions` also shows registry deprecations; a deprecated
dependency prints a warning on resolution (e.g. `tonyfettes/platform` →
"Use @async.platform instead").

### Browsing third-party source (`moon fetch`)

`moon fetch <author>/<module>[@<version>]` downloads a package's source into
`.repos/<author>/<module>/<version>/` for offline reading (examples, internals,
generated `.mbti`). It does NOT add the package to `moon.mod` — use `moon add`
for that. Add `.repos/` to `.gitignore`.

```sh
moon fetch moonbitlang/async@0.22.5
```

## `moon.mod` (module metadata)

```
name = "username/hello"
version = "0.1.0"
readme = "README.mbt.md"
repository = ""
license = "Apache-2.0"
keywords = []
description = "..."
preferred_target = "native"   # optional: default backend when none is specified
source = "src"                # optional: default is "."
private = true                # optional: `moon publish` refuses the module

import {
  "moonbitlang/x@0.4.6",
}
```

`source` is a top-level `moon.mod` field. Current `moon fmt` normalizes
`source` out of `options(...)` and rewrites it as `source = "src"`.

Use `moon add moonbitlang/x@0.4.6` and `moon remove moonbitlang/x` to manage the
`import` block instead of editing dependency versions by hand. For FFI/native
modules, set `preferred_target = "native"` so `moon build`/`moon test`/`moon run`
default to native.

**Legacy JSON manifests are rejected.** Since moon 0.1.20261016 ordinary
commands fail on `moon.mod.json` / `moon.pkg.json` with "no longer supported.
Run `moon fmt` to migrate". `moon fmt` converts them to `moon.mod` /
`moon.pkg` (deleting the JSON files) — run it, review the diff, commit. Never
create new JSON manifests.

## `moon.work` (workspace manifest)

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

## `moon.pkg` (package configuration)

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
pkgtype(kind: "executable")
```

`pkgtype(kind: ...)` sets the package kind: `"library"` (default),
`"executable"` (has `fn main`; replaces the deprecated
`options("is-main": true)`), or `"foreign_library"` (force-linked for foreign
consumers; replaces the deprecated `options(link: true)`). `moon fmt` rewrites
the deprecated spellings. Keep executables as entry points only: importing an
executable package from another package warns now and is slated to become an
error — move reusable code into a library package.

Use `supported_targets = "<target-set>"` at top level when the whole package
only supports selected backends: `"native"` (single), `"+js+wasm-gc"` (explicit
set), `"+all-js"` (all except js). `moon.mod` accepts the same field; the
effective set is the module∩package intersection.

```
supported_targets = "native"
pkgtype(kind: "executable")
```

Command behavior: `moon check/build/test/bench` keep only packages supporting
the selected target; `moon info` skips unsupported packages with a warning; if
a *required dependency* doesn't support the target, the command fails with a
dependency-path error. Omitting the field means all backends. For
backend-specific **main** packages, `supported_targets` must accompany
file-level `targets` — see the pitfall in "Conditional compilation".

Other top-level declarations (`moon fmt` moves the old `options(...)`
spellings to these):

- `formatter(ignore: [ "generated.mbt" ])` — files `moon fmt` skips (pre-build outputs are skipped automatically)
- `max_concurrent_tests = 2` — cap parallel tests in this package (shared ports/temp files); `moon test` runs test executables in parallel by default
- `regex_backend = "table"` — `auto` / `block` / `table` / `runtime`
- `virtual(...)` — see "Virtual packages" below

Settings without a direct form stay in `options(...)` (object keys inside
`{ }` must be quoted strings — unquoted keys are a parse error): `targets`,
`link`, `"native-stub"`, `overrides`, `"bin-name"`, `"bin-target"`, legacy
`"pre-build"`. `"test-import-all": true` is deprecated (`deprecated_syntax`
warning) — use explicit `using` declarations instead.

Packages are per directory. Directories without a `moon.pkg` are not recognized as packages.

### Virtual packages

A virtual package is an interface (declared in a `pkg.mbti` file) whose
implementation downstream users can swap — e.g. replacing
`moonbitlang/core/abort` behavior:

```
// interface package (pkg.mbti declares the API):
virtual(has_default: true)   // true = ships a fallback impl
// implementing package:
virtual(implement: "moonbitlang/core/abort")
// consumer (executable) package:
options(overrides: [ "moonbitlang/dummy_abort/abort_show_msg" ])
```

A package declares `virtual(...)` at most once — `has_default` and
`implement` cannot be combined. Consumers that don't list an override get the
default implementation (if `has_default` is true). The old spellings
`options("virtual": { "has-default": ... })` / `options(implement: ...)` are
still accepted and rewritten by `moon fmt`.

## Package importing & aliases

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

## `using` re-exports

`using` brings symbols from another package into the current one without the `@pkg.` prefix. With `pub using`, those symbols are also re-exported as part of the current package's public API:

```mbt nocheck
// In pkg_b
pub using @pkg_a { incr, type Counter, trait Tickable }
```

Now downstream callers can write `@pkg_b.incr(...)` and it resolves to `@pkg_a.incr(...)`. This is the cleanest way to:

- **Split a package gradually** — re-export from the new package, migrate callers one at a time, then move the actual definitions later (see `refactoring.md`).
- **Provide a curated facade** — collect symbols from several public packages into one public-facing one.

Without `pub`, the `using` form just brings names into local scope (no re-export). Don't conflate with the `import { ... }` block in `moon.pkg` — that adds a dependency edge, while `using` operates on already-imported packages.

### `internal/` packages

A package at `<a>/<b>/<c>/internal/<x>` is only importable from `<a>/<b>/<c>` and its descendants. Use this for implementation support that should not leak into your public API: scanners, parsers for sub-syntax, escaping/encoding helpers, validation helpers, low-level algorithms, private helper result types.

### Type ownership: `pub using` is for facade ergonomics, not type ownership

A package should own the public concrete types whose constructors, fields, pattern matching, and methods users are expected to use. If users think of a type as `@foo.X`, define `X` in package `foo` — or in a **non-internal public package** that `foo` re-exports. Public type ownership matters more than implementation locality.

Re-exporting a type from a non-internal public package works: MoonBit implicitly loads the owning package for method lookup, so users can name a value `@foo.X` and still call methods owned by `@bar.X`.

**Do not put public concrete types in `internal/*` and recover them via `pub using`.** External users do not get implicit method-owner loading for internal packages, so `x.method()` can fail even when `x` is typed as the facade's re-exported type. It also muddies constructors, generated interfaces, and privacy boundaries.

- Good: `pub using @parser { parse }`, `pub using @dom { type Node, to_markdown }` where `@parser` / `@dom` are public packages that own those APIs.
- Acceptable: `pub using @impl { decode_entities }` — a **value** from an internal package, if its signature exposes no internal types and it is intentionally public API.
- Avoid: `pub using @internal_impl { type X }` for a public concrete type. If `X` is public, define it in the facade or a public package; if truly internal, don't expose it.

When you need to translate internal helper results into public types, enforce public defaults, or hide internal helper types, write an explicit wrapper instead of `pub using`. Practical rule: if a public function returns `X` and users inspect, construct, match, or call methods on `X`, then `X` belongs in the facade package (or a public package it re-exports); helper packages under `internal/*` should keep their types internal or return simple helper result types.

## Standard library (moonbitlang/core)

The `moonbitlang/core` module is always available without adding it to
`moon.mod` dependencies. Ordinary core packages still need explicit `moon.pkg`
imports for package aliases such as `@utf8`, `@json`, or `@strconv`; add imports
like `"moonbitlang/core/encoding/utf8"` when the compiler reports a missing or
implicit core package. Both directions warn on moonc v0.10.16: naming `@json` /
`@test.Test` / `@bench.T` without the import is `core_package_not_imported`
(0071) — `derive(FromJson)` counts as using `@json` — and an import used only
through a prelude name (e.g. `Buffer()` with `core/buffer` imported) is
`unused_package` (0029).

The stdlib includes `@argparse` (`import { "moonbitlang/core/argparse" }`) —
the first choice for CLI argument parsing; never hand-roll an argv loop. API
guide and examples: `references/cli.md`.

## Creating packages

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

## Async IO

Moved to `async.md` — runtime setup (`moon.mod`/`moon.pkg` for
`moonbitlang/async`), `with_task_group` structured concurrency, spawn closure
syntax, `async test` configuration, cancellation-safe cleanup, and pipeline
backpressure.

## Conditional compilation

Gate individual `.mbt` files to backends/modes. `targets` goes inside
`options(...)`:

```
options(
  targets: {
    "wasm_only.mbt": [ "wasm" ],
    "js_only.mbt": [ "js" ],
    "debug_only.mbt": [ "debug" ],
    "wasm_or_js.mbt": [ "wasm", "js" ],
    "not_js.mbt": [ "not", "js" ],
    "complex.mbt": [ "or", [ "and", "wasm", "release" ], [ "and", "js", "debug" ] ],
  },
)
```

Available conditions:
- **Backends**: `"wasm"`, `"wasm-gc"`, `"js"`, `"native"`
- **Build modes**: `"debug"`, `"release"`
- **Logical operators**: `"and"`, `"or"`, `"not"`

**Backend-specific main packages need BOTH mechanisms.** File-level `targets`
controls which backends a *file* compiles on; package-level `supported_targets`
(see the `moon.pkg` section) controls which backends the *package* exists on.
A wasm-only executable with only `targets: { "main.mbt": ["wasm"] }` fails
`moon check --target native` with E4067 "Missing main function in the main
package" — main.mbt is skipped but the package is still an executable. Add
`supported_targets = "wasm"` so root-level checks skip the whole package
(explicitly checking that package path with `--target native` then errors with
"does not support target backend", which is the expected semantics).

### Single-module fullstack layout

One module can host `frontend/` (`supported_targets = "js"`), `backend/`
(`supported_targets = "native"`), and `shared/` (target-agnostic) packages —
per-package `supported_targets` lets each command build only the packages that
match its `--target`, while `shared/` compiles everywhere. Verify the whole
matrix with `moon check --deny-warn --target all` and `moon test --target all`.

## Link configuration

`link` lives inside `options(...)` with quoted keys. There is **no**
top-level `link(...)` declaration — `link(native(...))` is a parse error
("unexpected token native").

```
options(
  link: {
    "native": {
      "cc-flags": "-I/path/to/include",
      "cc-link-flags": "-L/path/to/lib -lmylib",
    },
  },
)
```

Full per-backend key set (`//` comments are annotations only). To force-link
a non-executable package, use `pkgtype(kind: "foreign_library")`, not the
deprecated boolean `link: true`.

```
options(
  link: {
    "wasm": {
      "exports": ["hello", "foo:bar"],
      "heap-start-address": 1024,
      "import-memory": {
        "module": "env",
        "name": "memory"
      },
      "memory-limits": {                 // linear memory min/max (pages)
        "min": 1,
        "max": 65536
      },
      "shared-memory": true,             // enable shared linear memory
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
  },
)
```

## Warning control

In `moon.mod` / `moon.pkg`, use the top-level `warnings` field.

```
warnings = "+unnecessary_annotation"  // enable warning 73
warnings = "+73"                      // equivalent
warnings = "-2-29"                    // disable unused variable and unused package
warnings = "@deprecated"              // promote a warning to a fatal error
warnings = "@alert-alert_unsafe"      // all alerts fatal, except category `unsafe` disabled
```

Prefixes: `-` disable, `+` enable, `@` enable and treat as error. Alerts
(warning 14) fire on APIs marked `#internal(<category>, ...)`; control one
category with `alert_<category>` or all at once with `alert`.

Use the same values on the command line with `--warn-list`:

```sh
moon check --warn-list +unnecessary_annotation
moon check --warn-list +73
```

Common warning numbers (moonc v0.10.16 defaults):
- `1` — unused function/value
- `2` — unused variable
- `11` / `partial_match` — partial pattern matching (**error** by default)
- `12` — unreachable code
- `25` / `test_unqualified_package` — blackbox test uses an implicitly imported name; write `@pkg.name`
- `29` / `unused_package` — unused import, now including unused explicit `moonbitlang/core/*` imports
- `71` / `core_package_not_imported` — core package used without an explicit `import`
- `73` / `unnecessary_annotation` — redundant annotations and over-qualified constructors (off by default)
- `82` / `ambiguous_braces` — bare `{}` (empty map / block / struct / JSON); write `Map([])`, `{ () }`, `T::{}`, or `Json::empty_object()`

Run `moon explain --diagnostics` to see all available warnings (mnemonic, id,
and default state).

## Pre-build commands (`rule` / `dev_build`)

Generate files before `moon check` / `moon build` / `moon test` — e.g. embed
external data as MoonBit code. In `moon.pkg` DSL:

```
rule(name: "embed", command: ":embed -i $input -o $output --name data --text")
dev_build(rule: "embed", input: "data.txt", output: "embedded.mbt")
```

- `rule(name:, command:)` declares a reusable command template; `$input` /
  `$output` are filled in by the `dev_build(rule:, input:, output:)` that uses
  it. Both may appear multiple times per file.
- `rule` can also live in `moon.mod` (module-level, visible to every package);
  lookup checks the package's own `moon.pkg` first, then `moon.mod`.
- Safety: pre-build does NOT run when the package is consumed as a dependency —
  commit the generated outputs so downstream builds work.
- Generated outputs are skipped by `moon fmt` automatically.

The older `options("pre-build": [{ "input": ..., "output": ..., "command": ... }])`
form still works; prefer `rule`/`dev_build`. Moon no longer runs `moonlex` /
`moonyacc` on `.mbl` / `.mby` files automatically: declare them as a
`dev_build` input with an explicit generator rule (an undeclared `.mbl`/`.mby`
in a package is a migration error), and commit the generated `.mbt`.

Generated code example:

```mbt check
///|
let data : String =
  #|hello,
  #|world
  #|
```

## More

- `toolchain.md` — `moon` commands, build artifacts, pre-commit checklist, `.mbtx` scripts
- `publishing.md` — publishing to mooncakes.io and advanced dependency tooling
- `refactoring.md` — package splits via `pub using`, API evolution shims
