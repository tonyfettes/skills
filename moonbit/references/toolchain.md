# MoonBit Toolchain Reference

Covers `moon` commands, the dev/test/commit workflow, spec-driven development,
and standalone `.mbtx` scripts.

For IDE navigation (`moon ide` subcommands), see `moon-ide.md`.
Module/package/workspace configuration (`moon.mod`, `moon.pkg`, `moon.work`,
imports, conditional compilation, link config, warnings, pre-build) is in
`project-config.md`.

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
- `moon fmt` — format code (rewrites files); `moon fmt --check` verifies without rewriting (CI)
- `moon check -w` / `moon build -w` — watch mode: re-run on file changes
- `moon doc --serve` — build and serve HTML docs locally (`-p <port>`, default 3000)
- `moon shell-completion --shell zsh` — print completion script (bash/zsh/fish/elvish/powershell)
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
- `moon test --build-only` — compile tests without running them
- `moon test -l 4` — cap snapshot-update passes for `-u` (default 256); lower it when a non-converging `inspect` keeps rewriting itself
- Doc tests run as part of plain `moon test`; the old `--doc` flag is deprecated (no-op)
- `moon bench` — run `bench` blocks; select with `-p <pkg> -f <file> -i <index>`, plus `--build-only` and `--no-parallelize`. See `optimization.md` ("Benchmarking with `@bench.T`").
- `moon coverage analyze` — coverage analysis. Common forms:
  ```
  moon coverage analyze -- -f summary                       # per-file %
  moon coverage analyze -- -f caret -F path/to/file.mbt     # caret marks under uncovered lines
  ```
  Run `moon test` first to collect data, then drive missing branches via the public API. See `refactoring.md` for the full workflow, and `testing.md` ("Code coverage") for report formats and CI upload.

Testing methodology (snapshot tests with the `inspect` family, black-box
defaults, docstring tests, `@test.T::snapshot`, error handling in tests) is in
`testing.md`. Benchmarks and profiling: `optimization.md`.

## README.mbt.md generation

Output `README.mbt.md` in the package directory.

- `*.mbt.md` files treat ` ```mbt check ` code blocks specially: they are included as code AND run by `moon check` / `moon test`.
- Use ` ```mbt nocheck ` for snippets that should only be syntax-highlighted (e.g. when just referencing types).
- If you only reference types from the package, prefer `mbt nocheck`.
- Symlink `README.mbt.md` → `README.md` so systems expecting `README.md` still find content.

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

## `.mbtx` standalone scripts

MoonBit `.mbtx` is a single-file script format that runs without a surrounding
`moon.mod`/`moon.mod.json` or `moon.pkg`. Dependencies are declared inline in
the script and resolved by the toolchain. Use it when replacing shell/Python
automation with MoonBit scripts or when working with existing `.mbtx` files.

**API Lookup Rule applies.** Before writing or explaining a `.mbtx` script that
uses library packages, follow the API Lookup Rule in `SKILL.md`. Do not copy
calls from old scripts without checking the current `.mbti`.

### Shape of a script

Scripts use normal MoonBit top-level blocks. Inline imports go at the top:

```moonbit
///|
import {
  "package/name",
  "package/name/subpackage",
}

///|
async fn main {
  ...
}
```

Use `async fn main` only when the script depends on async packages. Import the
base async package when the current async package docs require it.

Run scripts with the native target when they use packages backed by native
runtime or C FFI:

```sh
moon run --target native script.mbtx -- arg1 arg2
```

Arguments after `--` are passed to the script.

### Common script-specific checks

- Confirm import syntax from current `.mbtx` examples or parser behavior before
  editing many scripts.
- Confirm target support. Native, JS, and platform-specific packages differ.
- Confirm resource cleanup from README/tests/source instead of assuming a
  `finally`-style pattern.
- Confirm whether a helper creates missing files/directories, follows symlinks,
  inherits environment, or buffers output from the current interface and tests.
- Confirm regex syntax and JSON conversion behavior from current core package
  docs before writing parsing code.

## Library docs lookup

**Do NOT use context7 for MoonBit packages** — MoonBit is not indexed there. Use these instead:

1. `moon ide doc <query>` — best for project-local / stdlib symbols (see `moon-ide.md`)
2. `.mbti` files — API signatures of dependencies
3. `~/.moon/registry/cache/<org>/<pkg>/<version>.zip` — extracted source for installed deps
4. mooncakes.io — browser search
5. Library GitHub repo — when on mooncakes.io

## More

- `project-config.md` — `moon.mod` / `moon.pkg` / `moon.work`, imports & aliases, `using` re-exports, conditional compilation, link config, warning control, pre-build commands
- `moon-ide.md` — `moon ide` subcommand deep reference (goto-definition, find-references, tags, query syntax)
- `testing.md` — testing methodology and coverage workflow (`--enable-coverage`, report formats, CI upload)
- `publishing.md` — publishing to mooncakes.io and advanced dependency tooling
- `ffi/wasm-component.md` — Wasm Component Model (WIT, wit-bindgen, wasm-tools, wasmtime)
