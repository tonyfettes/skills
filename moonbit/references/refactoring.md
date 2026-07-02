# Refactoring Reference

Patterns for evolving MoonBit code without breaking callers. All assume you've already read the SKILL.md "Refactor (Behavior Preserving)" playbook and use `moon ide rename` / `find-references` / `outline` for navigation (see `moon-ide.md`).

## Migration shims for renaming and moving APIs

### Free function ↔ method: `#as_free_fn`

When you want to convert a free function `foo(x)` into a method `Bar::foo(self)`, place `#as_free_fn(foo, deprecated="Use Bar::foo")` on the new method. The compiler emits a deprecated free function `foo` that forwards to the method. Old callers keep working with a warning; you migrate them one at a time guided by the warnings.

```mbt nocheck
#as_free_fn(reader_next, deprecated="Use Reader::next instead")
fn Reader::next(self : Reader) -> Char? { ... }
// Old: reader_next(r)         — still compiles, emits deprecation warning
// New: r.next()
```

The reverse direction — exposing a method as a free function intentionally — uses the same attribute without `deprecated`:

```mbt nocheck
#as_free_fn(m)                            // public method exposed as `m()`
#as_free_fn(n, visibility="pub")          // also pick a visibility
fn List::f() -> Bool { true }
```

### Renaming an existing API: `#alias`

`#alias(old_name, deprecated)` adds an alternate (deprecated) name for an existing function. Use it when **renaming**, not when changing function-vs-method shape:

```mbt nocheck
#alias(compute_sum, deprecated="Use calculate_sum")
pub fn calculate_sum(a : Int, b : Int) -> Int { a + b }
```

Strip the alias once `find-references compute_sum` returns nothing.

### `#deprecated` for shape-preserving deprecation

If you don't need a forwarding shim — just want to discourage callers — `#deprecated("message")` annotates an existing item:

```mbt nocheck
#deprecated("Will be removed in 0.5; use BarV2")
pub fn old_api() -> Unit { ... }
```

Add `skip_current_package=true` when intra-package callers are intentional and don't need warnings.

## Splitting a package

Splitting `pkg_a` into `pkg_a` + `pkg_b` (extracting some symbols out):

1. **Create `pkg_b`** with its own `moon.pkg`. Re-export the moved symbols from `pkg_a` temporarily:

   ```mbt nocheck
   // In pkg_b
   pub using @pkg_a { incr, type Counter, trait Tickable }
   ```

   This makes `pkg_b.incr` resolve to the still-living `pkg_a.incr` so downstream code can switch one symbol at a time. `moon check` should pass before any caller migrates.

2. **Migrate callers** with `moon ide find-references <symbol>` and replace `@pkg_a.incr` → `@pkg_b.incr`.

3. **Move the actual definitions** from `pkg_a` to `pkg_b`. Drop the `using` re-export in `pkg_b` once the move is complete.

4. **Audit `pkg_a`'s `.mbti`** — symbols only kept public for `pkg_b` to re-export should be made private now that `pkg_b` owns them.

5. **Audit `pkg_b`'s `.mbti`** — only the symbols downstream actually called need to be `pub`.

### Acyclic dependencies

Lower-level packages must not import higher-level ones. If the split would create a cycle, the boundary is wrong — re-think it before re-exporting.

### `internal/` packages

Code under `<pkg>/internal/...` is only importable from `<pkg>` and its descendants. Use this for helpers that should not leak into your public API.

Do not move a **public concrete type** into `internal/*` and recover it with `pub using` from a facade — external users don't get implicit method-owner loading for internal packages, so `x.method()` can fail on the re-exported type. Public types belong in the package users name or a non-internal public package it re-exports; see "Type ownership" in `toolchain.md`.

## Coverage-driven gap filling

`moon coverage analyze` is what you reach for **after** `moon test` is green and you want to know which branches are still untested.

```bash
moon coverage analyze -- -f summary                            # per-file %
moon coverage analyze -- -f caret -F path/to/file.mbt          # caret marks under uncovered lines
```

Workflow:
1. Run `moon test` to collect coverage.
2. `moon coverage analyze -- -f summary` to find the lowest-coverage file.
3. `moon coverage analyze -- -f caret -F <file>` to see which lines/branches.
4. Add a black-box test through the public API that drives the missing branch. Avoid making something `pub` just to test it — that's an API regression dressed as test work.

## Style refactors that pay for themselves

These tend to come up over and over; do them as part of the broader refactor, not as separate PRs.

### Convert `match Some/None` to `unwrap_or` family

Already covered in `language.md` "Must-know gotchas." Reach for `unwrap_or`, `unwrap_or_else`, `map_or`, `map_or_else` when each match arm is "return value / return default".

### Pattern match directly instead of via small helpers

```mbt nocheck
// Before
match arr.get(0) {
  Some(v) => Iter::singleton(v)
  None    => Iter::empty()
}

// After
match arr {
  [v, ..] => Iter::singleton(v)
  []      => Iter::empty()
}
```

Direct pattern matching over collections also works for `String` / `StringView`:

```mbt nocheck
match s {
  ""              => ()
  [.."let", ..r]  => handle_let(r)
  _               => ()
}
```

### Use `is` patterns inside `if` / `guard`

Keeps branches concise without an extra `match`:

```mbt nocheck
match token {
  Some(Ident([.."@", ..rest])) if process(rest) is Some(x) => handle_at(rest, x)
  Some(Ident(name)) => handle_ident(name)
  None              => ()
}
```

### Replace C-style index loops with range loops

```mbt nocheck
// Before
for i = 0; i < len; i = i + 1 { items.push(fill) }
// After
for i in 0..<len { items.push(fill) }
// Or, when index is unused:
for _ in 0..<len { items.push(fill) }
```

### Convert imperative state loops to functional `for`

```mbt nocheck
// Before
let mut a = 1
let mut b = 2
for i = 0 {
  if i >= n { break }
  a = a + b
  b = b + a
  continue i + 1
}

// After (functional state in the loop header)
for _ in 0..<n; a = 1, b = 2 {
  continue b, a + b
} else {
  a
}
```

Once the state lives in the loop header, you can attach a `where { invariant: ..., reasoning: ... }` block when the algorithm warrants it (see `control-flow.md` "Loop invariants").

## When to stop

- A `pkg.generated.mbti` diff that grows during a refactor is a signal: re-check whether you accidentally widened the API.
- Local cleanups (renaming, pattern matching) before the high-level structure is sound is wasted effort. Settle the package boundary first, then tighten files.
- Aim: ≤ 10k lines per package, ≤ 2k lines per file, ≤ 200 lines per function. These are guides, not rules — break them deliberately.
