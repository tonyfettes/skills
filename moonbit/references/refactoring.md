# Refactoring & API Evolution

Patterns for evolving MoonBit code without breaking callers: package splits,
migration shims for published APIs, coverage-driven gap filling, and
readability refactors. All assume you've already read the SKILL.md "Refactor
(Behavior Preserving)" playbook and use `moon ide rename` / `find-references` /
`outline` for navigation (see `moon-ide.md`).

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

Do not move a **public concrete type** into `internal/*` and recover it with `pub using` from a facade — external users don't get implicit method-owner loading for internal packages, so `x.method()` can fail on the re-exported type. Public types belong in the package users name or a non-internal public package it re-exports; see "Type ownership" in `project-config.md`.

## Evolving public APIs (migration shims)

Shims and attributes for changing a published API without breaking callers:
renaming (`#alias`), fn↔method moves (`#as_free_fn`), deprecation
(`#deprecated`), parameter changes (`#label_migration`), visibility tightening
(`#visibility`), and usage warnings (`#alert`). Needed whenever a package has
external consumers — during feature work and releases, not just refactors.

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

### Evolving parameters: `#label_migration`

Changes a function's *parameter shape* without breaking callers — the shim
lives on the parameter, not on a duplicate function. Three forms (one
attribute per parameter; stack several on one function):

```mbt nocheck
#label_migration(x, fill=true, msg="x will become required")   // optional → required:
#label_migration(y, fill=false, msg="y will be removed")       //   warns on call sites that OMIT x
fn evolve(x? : Int = 0, y? : Int = 1) -> Int { ... }           // fill=false: warns on sites that PASS y

#label_migration(count, allow_positional=true)   // positional → labelled:
fn take(count~ : Int) -> Int { ... }             //   take(3) still compiles, warns to use count=3

#label_migration(size, alias=len, msg="len is renamed to size") // rename a label:
fn resize(size~ : Int) -> Int { ... }            //   resize(len=4) works; warns only if msg given
```

Verified: the warnings surface as `deprecated`-class warnings at exactly the
call sites that will break, so `moon check` output is the migration worklist.
Omitting `msg` on the `alias` form makes the old label a silent, permanent
alias — include `msg` when you intend to remove it.

### Announcing visibility tightening: `#visibility`

When a `pub(all)` type is headed for `readonly` or `abstract`, warn users
*before* the break. Usages that the future visibility would invalidate get an
`alert_visibility` warning now:

```mbt nocheck
#visibility(change_to="readonly", "Point will be readonly in the future.")
pub(all) struct Point {
  x : Int
  y : Int
}
// Downstream: Point::{ x: 1, y: 2 }  → warns (construction breaks under readonly)
//             p.x                    → no warning (reads stay legal)
```

`change_to="readonly"` flags construction and field mutation;
`change_to="abstract"` additionally flags pattern matching and field access.
Pass the message positionally — the `message=` keyword form crashed the
compiler on moon 0.1.20260629.

### Warning on use: `#alert(category, "msg")`

Attaches a warning to an API that fires at every call site — for `unsafe`,
`experimental`, or project-specific categories, without implying removal the
way `#deprecated` does:

```mbt nocheck
#alert(experimental, "parser API may change in 0.x")
pub fn parse_v2(s : String) -> Ast { ... }
// call sites warn: Warning (alert_experimental): parser API may change in 0.x
```

Control per category via the package warn-list: warning name is
`alert_<category>`, and `alert` addresses all categories (e.g.
`warnings = "@alert-alert_unsafe"` in `moon.pkg` = all alerts fatal except
`unsafe` disabled). Gotcha: `alert_unsafe` is **off by default** — an
`#alert(unsafe, ...)` is silent until the consumer opts in; pick another
category if you need the warning visible out of the box.

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

To exclude a function from coverage stats, use `#coverage.skip` — see `testing.md` ("Code coverage"; deprecated functions are excluded automatically).

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
} nobreak {
  a
}
```

Once the state lives in the loop header, you can attach a `where { proof_invariant: ..., proof_reasoning: ... }` block when the algorithm warrants it (see `control-flow.md` "Loop invariants").

## Review-driven readability rules

When writing or addressing review feedback for MoonBit code, apply these
readability checks across the touched file, not just the exact commented line:

- Prefer direct indexed iteration (`for index, item in array`) over
  `for index in 0..<array.length()` followed by `array[index]`.
- When parsing byte/char sequences, prefer array/`BytesView` patterns with rest
  segments — `[Esc, b'[', ..body, final]`, `[..b"\x1b]", ..rest]` — over
  index-arithmetic `if`/`else` chains, `match len` ladders, or manual guard
  sequences.
- Do not keep helpers that only return a constant, wrap a single obvious
  expression, or rename a trivial mutation. Inline them unless the helper
  enforces an invariant or names a real domain action.
- Prefer labeled/optional arguments on constructor functions over `.with_*`
  builder chains — `T::new(bg~, label?)`, not `T::new().with_bg(bg).with_label(l)`.
- Prefer `ArrayView`/`BytesView`/`StringView` parameters over defensive
  `copy()`/`to_owned()` — document aliasing in the docstring instead of cloning,
  especially on hot paths.
- Build strings with interpolation or a `StringBuilder`, not `+` concatenation
  chains or several parallel `mut String` accumulators.
- Do not introduce tuple destructuring merely to save a few lines. Prefer
  named locals or direct branches when values have separate meanings, especially
  in configuration and environment plumbing. Use tuples only when the grouped
  values are a cohesive domain result or an established local pattern.
- When application code needs to catch and render an expected domain or CLI
  error, define and raise a specific `suberror` instead of using `fail` and
  parsing its `Failure` text. Reserve `fail` for assertions, impossible states,
  quick tests, or errors that are intentionally not part of a typed handling
  path.
- In state-machine or index-arithmetic logic, add a short local comment for
  non-obvious boundary handling. Use compact ASCII diagrams when positions or
  offsets are hard to see from code.
- Centralize a repeated policy (normalization, filtering, width/limit
  computation, splitting rules) in the narrowest package that owns it; do not
  duplicate that logic in downstream consumer packages.
- Prefer black-box tests for behavior reachable through public package APIs.
  Keep white-box tests only for private state, cached layout metadata, or
  invariants that cannot be observed through the public API without widening it.

## When to stop

- A `pkg.generated.mbti` diff that grows during a refactor is a signal: re-check whether you accidentally widened the API.
- Local cleanups (renaming, pattern matching) before the high-level structure is sound is wasted effort. Settle the package boundary first, then tighten files.
- Aim: ≤ 10k lines per package, ≤ 2k lines per file, ≤ 200 lines per function. These are guides, not rules — break them deliberately.
