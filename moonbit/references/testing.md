# Benchmarks and Output Snapshots

For `inspect()` / `debug_inspect()` / `json_inspect()` snapshot tests, see `toolchain.md`. This file covers two specialized testing tools that aren't `inspect`-based:

- **`@bench.T`** — performance measurement with statistical reporting
- **`@test.T::snapshot`** — full-output snapshots for codegen, parsers, image renderers, etc.

## Benchmarking with `@bench.T`

A test block whose argument is `@bench.T` is run by `moon test` as a benchmark — `moon` reports timing statistics.

```mbt nocheck
fn fib(n : Int) -> Int {
  if n < 2 { return n }
  fib(n - 1) + fib(n - 2)
}

test (b : @bench.T) {
  b.bench(fn() { b.keep(fib(20)) })
}
```

Output:

```
time (mean ± σ)         range (min … max)
  21.67 µs ±   0.54 µs    21.28 µs …  23.14 µs  in 10 ×   4619 runs
```

`10 × 4619` — outer count × inner iteration count. The inner number is auto-tuned. Override the outer with `count`:

```mbt nocheck
test (b : @bench.T) {
  b.bench(fn() { b.keep(fib(20)) }, count=20)
}
```

### `b.keep(...)` is mandatory for pure functions

Without `b.keep`, the optimizer drops the call. `b.keep` is a method on `@bench.T` — there is no free-standing `keep` function.

### Batch comparison

Multiple `b.bench` calls in one test block compare implementations side-by-side:

```mbt nocheck
test (b : @bench.T) {
  b.bench(name="naive_fib", fn() { b.keep(fib(20)) })
  b.bench(name="fast_fib",  fn() { b.keep(fast_fib(20)) })
}
```

```
name      time (mean ± σ)         range (min … max)
naive_fib   21.01 µs ±   0.21 µs    20.76 µs …  21.32 µs  in 10 ×   4632 runs
fast_fib     0.02 µs ±   0.00 µs     0.02 µs …   0.02 µs  in 10 × 100000 runs
```

### Raw stats for further analysis

`@bench.single_bench` returns a `Summary` with min/max/mean/median/quartiles/stddev — JSON-serializable. Useful for plotting or regression detection in CI.

```mbt nocheck
fn collect_bench() -> Unit {
  let mut saved = 0
  let summary : @bench.Summary = @bench.single_bench(name="fib", fn() {
    saved = fib(20)
  })
  println(saved)                                       // touch saved so it's not dropped
  println(summary.to_json().stringify(escape_slash=true, indent=4))
}
```

Time units in the summary are microseconds. The `Summary` type's exact shape is not stability-guaranteed — treat it as observable JSON.

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
