# MoonBit Testing Guide

Correctness testing: snapshot tests with the `inspect` family, black-box
defaults, docstring tests, full-output snapshots (`@test.T::snapshot`), error
handling in tests, and the code-coverage workflow. Related files: `moon test`
command flags are in `toolchain.md`; performance measurement (`@bench.T`,
profiling) is in `optimization.md`.

## Snapshot tests with the `inspect` family

Snapshot tests are preferred — easy to update when behavior changes.

- **Snapshot tests**: write `inspect(value)` / `debug_inspect(value)` / `json_inspect(value)`, then run `moon test --update` (or `-u`) to fill in `content=`.
  - `inspect()` for values that implement `Show` (primitives, or types with a manual `impl Show`)
  - `debug_inspect()` for any type that derives `Debug` — the default for your own data types
  - `json_inspect()` for complex nested structures (uses `ToJson`, more readable output; `@json.inspect` is its deprecated old name — call it without a package prefix)
  - Encouraged to inspect the **whole return value** when it's not huge — makes tests simple. Derive `Debug` and/or `ToJson` (or `impl Show`) on `YourType` accordingly.
- **Update workflow**: after changing code that affects output, run `moon test --update`, review diffs in test files.
- **Black-box by default**: call only public APIs via `@package.fn`. Use white-box tests (`*_wbtest.mbt`) only when private members matter.
- **Grouping**: Combine related checks in one `test "..." { ... }` block for speed and clarity.
- **Panics**: Name tests with prefix `test "panic ..." {...}`. If the call returns a value, wrap it with `ignore(...)` to silence warnings.
- **Comparing two computed values** is `@debug.assert_eq` — `inspect(x, content=...)` / `debug_inspect` are for literal expected content; never interpolate the expected value into `content="\{y}"`.

## Skipping a test: `#skip`

`#skip` (or `#skip("reason")`) on a `test` block skips it at run time. The
block is **still type-checked**, so it can't rot silently — prefer this over
commenting a test out:

```mbt check
///|
#skip("blocked by external service")
test "not run, but still type-checked" {
  fail("never executes")
}
```

Skipped tests simply don't appear in the pass/fail totals.

## Docstring tests

Public APIs are encouraged to have docstring tests:

````mbt check
///|
/// Get the largest element of a non-empty `Array`.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(sum_array([1, 2, 3, 4, 5, 6]), content="21")
/// }
/// ```
///
/// # Panics
/// Panics if `xs` is empty.
pub fn sum_array(xs : Array[Int]) -> Int {
  xs.fold(init=0, (a, b) => a + b)
}
````

MoonBit code in docstrings is type-checked and tested automatically (via `moon test --update`). In docstrings, `mbt check` blocks should only contain `test` or `async test`.

**Doc tests are always blackbox.** They compile as black-box tests of the
package, so a doc test can only call the public API — a doc test on a *private*
definition cannot reference that definition (unbound identifier). Don't attach
example tests to private items; test them via `*_wbtest.mbt` instead.

## `.mbt.md` literate files

`*.mbt.md` files are black-box test files inside a package, and also work as
**standalone single-file projects**:

```bash
moon check README.mbt.md    # standalone: no moon.mod/moon.pkg needed
moon test  README.mbt.md
```

(Inside a project, keep using package-level `moon check` / `moon test`.)

The code-fence language id controls handling — there are four:

| Fence id | Semantics |
|---|---|
| `mbt` | compiled, but creates no test entry |
| `mbt check` | document-test code; put `test { .. }` / `async test` inside for assertions |
| `mbt nocheck` | displayed MoonBit, not compiled or tested |
| `moonbit` | ordinary display block, not compiled or tested |

Gotchas (verified with moon 0.1.20260629):

- All `mbt check` blocks in one file share a scope — a `fn` in one block is
  visible to a `test` in a later block.
- Plain `mbt` blocks were **not actually type-checked** by this toolchain
  version despite the documented semantics (a type error inside passed
  `moon check`/`moon test` silently). Put anything you want verified in
  `mbt check`.

Standalone files can declare YAML front matter for imports and target:

```markdown
---
moonbit:
  import:
    - moonbitlang/core/ref              # string form
    - path: moonbitlang/core/ref        # map form with explicit alias
      alias: ref
  backend:
    js                                  # target backend for this file
---
```

Use `moonbit.import` to name importable packages directly (third-party
entries take the form `username/module@version/package`). Use `moonbit.deps`
(a `module: version` map) to declare module dependencies and let Moon
synthesize imports — but note `deps` without `import` imports *all* packages
of the module (legacy behavior, warns); prefer explicit `import`.

## Full-output snapshots with `@test.T::snapshot`

For tests where you want to capture the **entire output** of a process (codegen, formatter, renderer, parser pretty-printer), use `@test.T`:

```mbt nocheck
test "record anything" (t : @test.T) {
  t.write("Hello, world!")
  t.writeln(" And hello, MoonBit!")
  t.snapshot(filename="record_anything.txt")
}
```

`moon test --update` writes (and refreshes) the snapshot under `__snapshot__/<filename>` in the package. On subsequent runs, the test compares actual output to the saved file and fails on diff.

### When to use this over `inspect`

| Use | When |
|---|---|
| `inspect(value, content=...)` | The value implements `Show` (primitives or a manual `impl Show`) |
| `debug_inspect(value, content=...)` | Your own data types — anything that derives `Debug` |
| `json_inspect(value, content=...)` | Nested structures; `ToJson` produces clearer diff |
| `@test.T::snapshot(filename=...)` | Output is multi-line/binary-ish; or you want to record a whole pipeline run, not a single value |

### Constraints

- **`t.snapshot` raises** — put it at the **end** of the test block. Anything after it is unreachable.
- One snapshot per filename per test block. Use distinct filenames if you want to record multiple artifacts in one test.
- Snapshots are checked into version control alongside the test.

## Error handling in tests

- **Expected success**: call the raising function directly — if it unexpectedly raises, the test fails with the actual error.
- **Expected failure**: `try f() catch { err => inspect(err) } noraise { _ => fail("expected to fail") }`.

**Never use `abort(...)` in a test** — not even for a "this can't happen" branch
(e.g. an unreachable arm added only to make a `catch` exhaustive). `abort` panics
the test runner instead of producing a test failure, and it usually signals a
design smell in the code under test rather than a real test need.

Prefer, in order:

1. **Re-raise / let it propagate.** A `test` block can raise, so don't catch
   what you don't assert on. If a `catch` was added only to satisfy
   exhaustiveness over an error you don't expect, re-raise it (`e => raise e`) so
   an unexpected error fails the test with its real value, or restructure so the
   call propagates directly. An over-broad error type that forces spurious arms
   is itself the thing to fix (often: the error variant belongs in a different
   layer — keep each error set narrow to its domain).
2. **`fail("...")`** when you genuinely need to stop a test with a message (e.g.
   a value that should have matched a pattern didn't). `fail` produces a test
   failure; `abort` produces a crash.

```moonbit nocheck
// Anti-pattern: panics the runner, and the WrongAtlas arm only exists because
// the error type is too wide for this call site.
let r = atlas.reserve(w, h) catch {
  AtlasFull => { full = true; break }
  WrongAtlas => abort("reserve never raises WrongAtlas")  // ✗
}

// Better: narrow the error so reserve only raises AtlasFull (fix the design), or
// re-raise the unexpected case so it surfaces as a real failure.
let r = atlas.reserve(w, h) catch {
  AtlasFull => { full = true; break }
  e => raise e                                            // ✓ propagate
}
```

## Update workflow

`moon test --update` (or `-u`) writes/refreshes snapshots for both `inspect` content and `@test.T::snapshot` files. Review the resulting diff in test files / `__snapshot__/` before committing.

## Code coverage

Full coverage workflow: instrument tests, generate reports in multiple formats,
upload to CI services. Coverage is **branch-based** — each coverage point is the
start of a branch, counted per execution.

For quick gap-hunting during development, `moon coverage analyze` (below) is
usually all you need; the manual `moon test --enable-coverage` + `moon coverage
report` pipeline is for CI and report files.

### Quick analysis (one command)

`moon coverage analyze` runs tests with instrumentation AND reports in one step.
Flags after `--` go to the report tool:

```sh
moon coverage analyze -- -f summary                     # per-file covered/total
moon coverage analyze -- -f caret -F path/to/file.mbt   # caret marks under uncovered lines
moon coverage analyze -p mymod/mypkg -- -f summary      # limit to one package
```

Workflow: run it, then drive uncovered branches through the **public API** (add
tests, don't contort the code). See `refactoring.md` for the full loop.

### Manual pipeline (test, then report)

```sh
moon test --enable-coverage      # recompiles with instrumentation if needed
moon coverage report -f summary  # consume the collected data
```

`moon test --enable-coverage` drops `moonbit_coverage_*.txt` files under the
build directory (e.g. `_build/wasm-gc/debug/test/`); `moon coverage report`
picks them up from there.

#### Report formats (`-f`)

| Format | Output | Use when |
|---|---|---|
| `summary` | stdout, `file: covered/total` per file | quick per-file % check |
| `caret` | stdout, carets under uncovered code | pinpointing exact uncovered branches |
| `bisect` (default) | `bisect.coverage` file | OCaml Bisect tooling |
| `coveralls` | `coveralls.json` | Coveralls / CodeCov upload (line-based JSON) |
| `cobertura` | Cobertura XML | Jenkins/GitLab-style CI dashboards |
| `html` | `_coverage/` directory | human browsing |

Other useful report flags (see `moon coverage report --help` for all):
`-o <file>` output path, `-p <pkg>` / `-F <file>` limit scope,
`--ignore-missing-files`, `--absolute-file-paths`.

#### HTML report

`moon coverage report -f html` writes `_coverage/`; open `index.html` for the
file list with percentages. In per-file pages, each coverage point is a
highlighted character: green = covered, red = not covered; yellow lines are
partially covered. Unhighlighted lines are not branch starts — they share the
coverage of the closest covered line above.

### CI integration (Coveralls / CodeCov)

`--send-to coveralls|codecov` uploads directly. GitHub Actions example:

```sh
moon test --enable-coverage
moon coverage report \
    -f coveralls \
    -o codecov_report.json \
    --service-name github \
    --service-job-id "$GITHUB_RUN_NUMBER" \
    --service-pull-request "${{ github.event.number }}" \
    --send-to coveralls
# env: COVERALLS_REPO_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Related flags: `--coveralls-token`, `--service-number`,
`--coveralls-parallel` (parallel builds), `--coveralls-include-git-info`.

### Cleaning up

```sh
moon coverage clean   # remove coverage artifacts (stale data skews reports)
```

Run it when switching branches or after large refactors, so old
`moonbit_coverage_*` files don't pollute the next report.

### Skipping coverage

- Attribute `#coverage.skip` on a function excludes all its coverage points.
- Deprecated functions are automatically excluded — no need to chase 100% on
  code kept only for compatibility.
