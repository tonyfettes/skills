---
name: moonbit
description: Authoritative MoonBit reference — syntax (newtype/struct/trait/type/enum), project layout (moon.mod/moon.pkg/moon.work), tooling (moon check/test/fmt/info/ide/run/build), C FFI (`extern "c"`, moonbit.h, ownership, ASan), .mbtx scripting. Load BEFORE writing or proposing ANY MoonBit code (even a 2-line snippet in a design discussion), running any `moon` command, reading .mbt/.mbti/.mbtx files, or discussing MoonBit syntax/APIs. Triggers - .mbt/.mbtx/.mbti files, moon.mod/moon.mod.json/moon.pkg/moon.pkg.json/moon.work in cwd, @pkg references, `extern "c"`, any `moon ...` command, any MoonBit keyword or syntax in conversation. Do not guess MoonBit syntax from training — consult this skill's references.
---

# MoonBit

Authoritative guide for writing, refactoring, testing, and binding MoonBit projects.

## Route to references by task

Load the reference matching your current work BEFORE writing code:

| Task | Read |
|---|---|
| Writing MoonBit syntax — core (structs/enums/newtypes, pattern matching, visibility, constants, options, label/optional params) | `references/language.md` |
| Strings, `StringView`, UTF-16 safety, interpolation (`<+`/`<?`), `Bytes`, Arrays, `Map`, views | `references/strings-data.md` |
| Error handling (`suberror`, `raise`/`catch`/`noraise`, `raise?`, `try`) | `references/errors.md` |
| Loops and control flow (`for`, functional `loop`, `while`, labelled loops, loop invariants) | `references/control-flow.md` |
| Methods, traits, operator overloading, indexing operators (`#alias`) | `references/traits-methods.md` |
| Configuring `derive(...)` — JSON enum styles, rename rules, container/case/field args | `references/derive.md` |
| Running `moon` commands (check / build / test / fmt / info / run) | `references/toolchain.md` |
| Project/package layout, imports, `moon.mod`, `moon.pkg` config, dependencies, `using` re-exports | `references/toolchain.md` |
| Multi-module workspaces (`moon.work`, `moon work init/use/sync`) | `references/toolchain.md` |
| Designing visibility and public API shape (`pub`, opaque types, `.mbti` review) | `references/language.md` + `references/toolchain.md` |
| Refactoring (API shrinkage, package splits, fn↔method, coverage gap filling) | `references/refactoring.md` |
| Optimizing data layout with `#valtype` (unboxing, flat arrays, value enums, the visibility interaction) | `references/valtype.md` |
| Optimizing hot-path code on the native backend (refcount traffic, polymorphic `Eq` on enums, cross-package inlining, reading generated C/asm, profiling method) | `references/optimization.md` |
| SIMD with the experimental `V128` type (`@v128` lane ops, wasm SIMD128 mirror) | `references/optimization.md` |
| Benchmarks (`@bench.T`) and full-output snapshots (`@test.T::snapshot`) | `references/testing.md` |
| Code navigation with `moon ide` (outline/peek-def/find-references/rename/hover/doc) | `references/moon-ide.md` |
| Binding a C library (`extern "c"`, stubs, ownership, callbacks, ASan) | `references/c-ffi.md` (+ topic-specific c-ffi-*.md) |
| Writing standalone `.mbtx` scripts (CLI tools, subprocess, FS, JSON, regex) | `references/mbtx.md` |
| Conditional compilation, link configuration, pre-build commands, warning control | `references/toolchain.md` |

## API Lookup Rule

Do not answer MoonBit library API questions from memory, training data, or
snippets copied into this skill.

Before answering questions about a package API or writing code that uses one,
resolve `MOON_HOME`:

```sh
printf '%s\n' "${MOON_HOME:-$HOME/.moon}"
```

For `moonbitlang/core/*`, read the current files under:

```text
${MOON_HOME}/lib/core/
```

Start from `<package>/pkg.generated.mbti` or `<package>/pkg.mbti`. Read
README/source/tests when behavior, target support, examples, or edge cases
matter.

For registry packages, including `moonbitlang/async`, first read the project
`moon.mod` (or legacy `moon.mod.json`) to find the pinned dependency version.
Then inspect:

```text
${MOON_HOME}/registry/cache/<owner>/<package>/<version>.zip
```

Read the relevant `pkg.generated.mbti` inside the archive first, then README,
source, tests, and examples when behavior matters. Use
`${MOON_HOME}/registry/symbols/<owner>/<package>/<version>.symbols` if present,
or `moon ide doc` / `moon ide peek-def` for semantic lookup.

Treat `.mbti` files as the public contract. Quote or summarize signatures only
after reading the current local files. Do not claim an API is unavailable unless
the current pinned package interface and package search support that conclusion.

If you are about to write MoonBit syntax you have not verified, read the matching reference first (`references/language.md` for core syntax; `strings-data.md`, `errors.md`, `control-flow.md`, `traits-methods.md` for those topics). The language has evolved — training-era syntax may be wrong.

Pay special attention to:
- newtype conventions (`struct NewType(OldType)` with `.0` access) — `language.md`
- visibility defaults and opaque/public type choices — `language.md`
- string safety rules (`String[i]` returns `UInt16`, may abort, and slicing can also abort) — `strings-data.md`
- ASCII-vs-Unicode text handling patterns, `Char::to_ascii_lowercase` / `to_ascii_uppercase` — `strings-data.md`

## Agent Workflow

1. **Clarify goal and constraints.** Confirm expected behavior, non-goals, and compatibility constraints (target backend, public API stability, performance limits). Decide early whether the task should change public API at all.

2. **Locate module/package boundaries.** Find `moon.mod` (module root; legacy projects may still use `moon.mod.json`) and relevant `moon.pkg` / `moon.pkg.json` files (package boundaries and imports).

3. **Discover APIs before coding.** Prefer `moon ide doc` queries to find existing functions/types/methods before adding new code. Use `moon ide outline`, `moon ide peek-def`, and `moon ide find-references` for semantic navigation. See `references/moon-ide.md`.

4. **Reliable refactoring.** Use `moon ide rename` for semantic rename. If multiple symbols share a name, add `--loc filename:line:col`. Use `#deprecated` (and `#alias(old_api, deprecated)` for temporary shims) for migrations; remove them once callers are updated.

5. **Edit minimally and package-locally.** Keep changes inside the correct package, use `///|` top-level delimiters, split code into cohesive files.

6. **Model visibility deliberately.** Default to the smallest public surface that serves an external consumer:
   - functions are private unless they are intentional package API
   - prefer opaque exported types (`struct` / `enum` without `pub`) over readable public records when callers do not need field access or pattern matching
   - use `priv` when the type name itself should not appear in `.mbti`
   - use `pub struct` only when outside code should read fields or pattern-match
   - use `pub(all)` rarely, only when outside construction is part of the contract
   - internal state machines, parse tables, accumulators, and helper parsers should stay internal
   - white-box tests are not justification for making internals public
   - public concrete types belong in the package users name (or a public package it re-exports) — never defined in `internal/*` and recovered via `pub using`; see "Type ownership" in `references/toolchain.md`
7. **Validate in a tight loop.** `moon check` after edits; add `--warn-list +unnecessary_annotation` (equivalent to `--warn-list +73`) when cleaning redundant annotations and over-qualified constructors. `moon test [dirname|filename] --filter 'glob'` for targeted tests. `moon test --update` for snapshot changes.

8. **Finalize before handoff.** Always run `moon fmt` and `moon info` before committing — the user expects formatted code and up-to-date `.mbti` files in every commit. Review `pkg.generated.mbti` for necessity, not just change: remove unjustified public items and public mutable fields before considering the task done. Report changed files, validation commands, and any remaining risks.

## Review-Driven Readability Rules

When writing or addressing review feedback for MoonBit code, apply these
readability checks across the touched file, not just the exact commented line:

- Prefer direct indexed iteration (`for index, item in array`) over
  `for index in 0..<array.length()` followed by `array[index]`.
- Prefer `if expr is Some(value) { ... } else { ... }`, and chain it with
  related boolean conditions when that removes a nested `match` without hiding
  behavior. For early-exit shapes, prefer `guard expr is Some(value) else { ... }`.
  Do not `match` an Option.
- Prefer optional argument forwarding when passing an optional parameter through
  unchanged. If a callee accepts `arg? : T` and the caller already has an
  optional parameter `arg? : T`, forward it as `inner(value?)` — do not unwrap
  and rewrap by hand with `if value is Some(value) { inner(value~) } else { inner() }`.
- Do not keep helpers that only return a constant, wrap a single obvious
  expression, or rename a trivial mutation. Inline them unless the helper
  enforces an invariant or names a real domain action.
- Do not introduce tuple destructuring merely to save a few lines. Prefer
  named locals or direct branches when values have separate meanings, especially
  in configuration and environment plumbing. Use tuples only when the grouped
  values are a cohesive domain result or an established local pattern.
- When application code needs to catch and render an expected domain or CLI
  error, define and raise a specific `suberror` instead of using `fail` and
  parsing its `Failure` text. Reserve `fail` for assertions, impossible states,
  quick tests, or errors that are intentionally not part of a typed handling
  path.
- Treat `mut Array[_]` as suspicious. Use `mut` only when the array variable is
  reassigned; pushing or mutating array contents does not by itself need a
  mutable binding.
- In state-machine or index-arithmetic logic, add a short local comment for
  non-obvious boundary handling. Use compact ASCII diagrams when positions or
  offsets are hard to see from code.
- Centralize a repeated policy (normalization, filtering, width/limit
  computation, splitting rules) in the narrowest package that owns it; do not
  duplicate that logic in downstream consumer packages.
- Prefer black-box tests for behavior reachable through public package APIs.
  Keep white-box tests only for private state, cached layout metadata, or
  invariants that cannot be observed through the public API without widening it.

## Fast Task Playbooks

Use the smallest playbook that matches the request.

### Bug Fix (No API Change Intended)

1. Reproduce or identify the failing behavior.
2. Locate symbols with `moon ide outline`, `moon ide peek-def`, `moon ide find-references`.
3. Implement minimal fix in the current package.
4. Validate: `moon check` → targeted `moon test` → `moon fmt` → `moon info` (confirm `pkg.generated.mbti` unchanged).

### Refactor (Behavior Preserving)

1. Confirm behavior/API invariants first.
2. Prefer semantic tools: `moon ide rename`, `moon ide find-references`, `moon ide peek-def`. Use `--loc filename:line:col` when names are ambiguous.
3. Keep edits package-local and file-organization-focused.
4. Re-check whether any currently public type or field can be made opaque/private as part of the refactor without changing the intended API contract.
5. Validate: `moon check` → `moon test` → `moon fmt` → `moon info` (API should remain unchanged unless requested).

For migration shims (`#as_free_fn`, `#alias(old, deprecated)`), package splits via `pub using` re-export, and coverage-driven gap filling, see `references/refactoring.md`.

### New Feature or Public API

1. Discover existing idioms with `moon ide doc` before introducing new names.
2. Choose the minimum necessary visibility:
   - start from private/internal
   - make types opaque by default
   - only expose readable fields, constructors, or mutation when external callers truly need them
3. Add implementation in cohesive files with `///|` delimiters.
4. Add/extend black-box tests and docstring examples for public APIs.
5. Validate: `moon check` → `moon test` (use `--update` for snapshots when needed) → `moon fmt` → `moon info` (review and keep only intended `pkg.generated.mbti` changes).

## Project Layouts

MoonBit uses `.mbt` for source files and `.mbti` for interface files. At the top of a project there is a `moon.mod` file with module metadata. The project may contain multiple packages, each with `moon.pkg` (preferred) or `moon.pkg.json` (legacy). Subdirectories can also contain `moon.mod` to scope a different dependency set. Legacy projects may still contain `moon.mod.json`; treat it as the old module metadata format and migrate/update guidance to `moon.mod` instead of creating new `moon.mod.json` files. Repos with **multiple modules** add a `moon.work` workspace manifest at the root listing member modules — see `references/toolchain.md` (`moon work init/use/sync`).

### Example layout

```
my_module
├── moon.mod                  # Module metadata; source option can specify source dir
├── moon.pkg                  # Package metadata (each directory is a package like Go)
├── README.mbt.md             # Markdown with tested code blocks (`test "..." { ... }`)
├── README.md -> README.mbt.md
├── cmd/
│   └── main/
│       ├── main.mbt
│       └── moon.pkg          # executable package with `options("is-main": true)`
├── liba/                     # Library package
│   ├── moon.pkg              # Referenced as `@username/my_module/liba`
│   └── libb/                 # Nested package
│       └── moon.pkg          # Referenced as `@username/my_module/liba/libb`
├── user_pkg.mbt              # Root package files
├── user_pkg_wbtest.mbt       # White-box tests (access private members)
└── user_pkg_test.mbt         # Black-box tests
```

- **Module**: characterized by `moon.mod`. Like a Go module — a collection of packages, usually one per repo. Module boundaries matter for dependency management and import paths.
- **Package**: characterized by `moon.pkg` (or `moon.pkg.json`). The compilation unit (like a Go package). All source files in a package share definitions. Package name = module name + relative path to package dir (NOT file names). Imports refer to module + package paths, NEVER to file names. All `moon` subcommands execute in the module root, not the current package.
- **Files**: `.mbt` files are just chunks of source inside a package. File names do NOT create modules/packages/namespaces. You may freely split/merge/move declarations between files in the same package — any declaration can reference any other in the same package.

### Coding/layout rules you MUST follow

1. **Prefer many small, cohesive files** over one large file. Group related types and functions (e.g. `http_client.mbt`, `router.mbt`). Split when a file is getting large or unfocused.

2. **You MAY freely move declarations** between files inside the same package. Each block is separated by `///|`. Moving a function/struct/trait between files does not change semantics. Refactoring by splitting/merging files is safe.

3. **File names are purely organizational.** Don't assume file names define modules, don't put file names in type paths. Choose file names by feature or responsibility.

4. **When adding new code**, prefer adding to an existing file that matches the feature. If no good file exists, create a new one with a descriptive name. Avoid giant "impl", "misc", or "util" files.

5. **Tests**: Place in dedicated `*_test.mbt` files in the appropriate package. `*.mbt.md` files are also black-box test files — code blocks tagged ` ```mbt check ` are treated as test cases and serve both as docs and tests. `README.mbt.md` with `mbt check` examples is encouraged; symlink to `README.md` for GitHub compatibility.

6. **Interface files (`pkg.generated.mbti`)**: compiler-generated summaries of a package's public API. Useful for code review. Check them into version control — commits that don't change public APIs leave these files unchanged. Generated by `moon info`; never edit them by hand (not even whitespace cleanup) — regenerate and review the diff as the public-API signal.

7. **Public API minimization**: treat every `.mbti` entry as an API promise.
   - Public mutable fields are almost always wrong.
   - Internal helper types should not leak into `.mbti`.
   - White-box tests should use package visibility, not force broader API exposure.

## Common Pitfalls

- **Don't use uppercase for variables/functions** — compilation error
- **Don't forget `mut` for mutable record fields** — immutable by default (Arrays typically do NOT need `mut` unless completely reassigning the variable; `push` etc. do not require it)
- **Don't ignore error handling** — errors must be explicitly handled
- **Do not introduce `abort` without explicit user approval** — before writing MoonBit code that calls `abort`, pause and ask the user to confirm that aborting is the intended behavior. Only use `abort` after that confirmation; otherwise model the failure with a typed error/`raise`, `Result`, or an approved adapter.
- **Do not write `guard` without `else` without explicit user approval** — `guard cond` / `guard x is Pattern` with no `else` panics at runtime when the condition fails; treat it with the same severity as `abort`. Default to `guard ... else { ... }` with an early return, typed error, or fallback. In tests too: prefer raising via `guard ... else { fail("...") }` over panicking.
- **Don't `match` an Option** — use `x.unwrap_or(...)` (and friends) for trivial defaults, `if x is Some(v) { ... } else { ... }` for branching, or `guard x is Some(v) else { ... }` for early exit. Reserve `match` for enums with several meaningful arms.
- **Don't swallow all async errors** — in async code, never write a catch-all
  branch like `catch { _ => () }`. If a catch-all is genuinely needed for a
  user-visible best-effort operation, first preserve cancellation with
  `error if @async.is_being_cancelled() => raise error`. If cancellation itself
  should be swallowed, discuss that behavior with the user before doing it.
- **Don't use `return` unnecessarily** — the last expression is the return value
- **Don't create methods without `Type::` prefix** — methods need explicit type prefix
- **Don't forget to handle array bounds** — use `get()` for safe access
- **Don't forget `@package` prefix** when calling functions from other packages
- **Don't use `++` or `--`** (not supported) — use `i = i + 1` or `i += 1`
- **Don't add explicit `try` for error propagation** — inside a `raise` function, call error-raising functions normally; use `catch` to handle locally and `try!` only when aborting is intended
- **Legacy syntax**: older code may use `function_name!(...)` or `function_name(...)?` — these are deprecated; use normal calls for propagation. `try?` (convert to `Result`) is also being deprecated — prefer `try ... catch ... noraise`
- **Don't write an empty parameter list for `main`** — use `fn main { ... }` or `fn main raise { ... }`, not `fn main() { ... }`
- **Don't write record-style enum/error constructor fields** — labeled constructor fields use `label~ : Type`, e.g. `InvalidNumber(input~ : String)`, not `InvalidNumber(input : String)`
- **Don't manually forward optional arguments by branching on `Some`/`None`** — if both caller and callee use `arg? : T`, pass it through as `arg?`; do not write two calls like `if arg is Some(arg) { f(arg~) } else { f() }`.
- **Prefer range `for` loops** over C-style — `for i in 0..<(n-1) {...}` and `for j in 0..=6 {...}` are more idiomatic
- **Don't use `for { ... }` for infinite loops** — write `for ;; { ... }` instead
- **Don't `derive(Show)` for debugging** — derive `Debug` and use `debug_inspect()` for test/diagnostic output (`\{to_repr(value)}` for interpolation of composed values). Reserve a manual `impl Show` for specialized display formats (JSON, XML, domain text)
- **Don't call `@json.inspect()`** — use the prelude `json_inspect(value, ...)` without a package prefix
- **Async** — MoonBit has no `await` keyword; do not add it. Async functions/tests are marked with the `async` prefix (e.g. `[pub] async fn ...`, `async test ...`). Async functions default to raising, so do not add `raise`; add `noraise` only when the async body must not raise.
- **No `finally`** in MoonBit — handle cleanup in both try success and catch paths
- **No cross-package extension methods** — you cannot define `@otherpkg.Type::method` from outside that type's own package. Use free functions or define a trait and `impl Trait for @otherpkg.Type` instead.
- **Do NOT use context7** for MoonBit library lookups — MoonBit packages aren't indexed there. Use `moon ide doc`, mooncakes.io, the moon registry cache (`~/.moon/registry/cache/`), `.mbti` files, or the library's source/GitHub instead.
- **Don't use `moonbitlang/x` for IO** (e.g. `moonbitlang/x/fs` file read/write) — always prefer `moonbitlang/async` for filesystem, network, and other IO. Only reach for `moonbitlang/x` IO when the user explicitly asks for it. `moonbitlang/x` is a staging/experimental grab-bag; its IO surface is not the supported path.

For complete syntax details, see `references/language.md` (and its topic files `strings-data.md`, `errors.md`, `control-flow.md`, `traits-methods.md`). For `moon` tooling, see `references/toolchain.md` and `references/moon-ide.md`.
