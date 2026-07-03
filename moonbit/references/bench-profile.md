# Benchmarks and Profiling

Measuring performance: `@bench.T` micro-benchmarks and the native profiler.
Never assert that a change is faster or slower without one of these — propose
the measurement first, then conclude (this applies to review comments and
design discussions, not just committed optimizations). What to *fix* once
you've measured — refcount traffic, polymorphic `Eq`, inlining — is in
`optimization.md`.

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

## Profiling (native)

The bottleneck is usually not what you're staring at — profile before
optimizing.

```sh
moon run ./bench/<name> --release --target native --profile
```

Read **"Top self time"** and especially **"Runtime leaf costs attributed to
MoonBit callers"** — the latter pins `moonbit_incref/decref_inlined` samples
onto the MoonBit function whose machine code contains them (incref/decref
inline into the caller, so a `callee <- moonbit_decref_inlined` line means
the cost lives in `callee`'s body, often from a *different* source function
that clang inlined into it).

If a profile frame shows a raw mangled C symbol (`_M0...`), decode it with
`moon tool demangle _M0MP26tester4demo5Point4norm` →
`@tester/demo.Point::norm` (see `optimization.md`).

### Before/after methodology

Profiling is noisy at a few hundred 1 ms samples. For an honest before/after,
`git stash` the change, rebuild, run the bench **3–4×**, then pop and run
3–4× again, comparing means. A single baseline run will mislead you.

Once you know the hot function, verify what the compiler actually did by
reading the generated C and assembly — see `optimization.md` ("Golden rule").
