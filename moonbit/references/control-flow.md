# MoonBit Control Flow

Expressions-as-values, range/functional `for` loops, the functional `loop`, `while` as an expression, and labelled loops/blocks. Split out of `language.md`.

## Control flow

### Expressions are values

`if`, `match`, loops all return values; the last expression is the return:

```mbt check
///|
test "expressions return values" {
  let n = 1
  let msg : String = if n > 0 { "pos" } else { "non-pos" }
  let res : String = match n {
    0 => "zero"
    1 => "one"
    _ => "many"
  }
  inspect(res, content="one")
  inspect(msg, content="pos")
}
```

(Don't use a two-arm Option `match` to demonstrate this — for Options, use
`unwrap_or` / `if x is Some(v)` / `guard x is Some(v) else`; see `language.md`.)

### Pipe operator `|>`

`x |> f` is `f(x)`; `x |> f(y)` inserts `x` as the **first** argument — `f(x, y)`.
Useful for left-to-right data pipelines across free functions and `Type::method`
references:

```mbt check
///|
fn add(a : Int, b : Int) -> Int {
  a + b
}

///|
test "pipe" {
  let r = [3, 1, 2]
    |> Array::map(x => x * 10)
    |> Array::fold(init=0, add)
  inspect(r, content="60")
}
```

The reverse pipe `f <| x` is `f(x)` (right-associative). It reads well for
DSL-ish trailing arguments — e.g. `h1 <| [ ... ]` in rabbita views, and similar
patterns in `moonbitlang/async` code. To pipe into a non-first argument, use an
arrow lambda — the body needs braces (or parenthesize the whole lambda):
`x |> y => { f(a, y) }`. A bare `x |> y => f(a, y)` is a parse error.

### Functional `for` loop

```mbt check
///|
pub fn binary_search(arr : ArrayView[Int], value : Int) -> Result[Int, Int] {
  let len = arr.length()
  // for: initial state; [predicate]; [post-update] {
  //   body — `continue` updates state
  // } nobreak { exit block }
  for i = 0, j = len; i < j; {
    let h = i + (j - i) / 2
    if arr[h] < value {
      continue h + 1, j
    } else {
      continue i, h
    }
  } nobreak {
    if i < len && arr[i] == value { Ok(i) } else { Err(i) }
  } where {
    proof_invariant: 0 <= i && i <= j && j <= len,
    proof_invariant: i == 0 || arr[i - 1] < value,
    proof_invariant: j == len || arr[j] >= value,
    proof_reasoning: (
      #|For a sorted array, boundary invariants are witnesses:
      #|  arr[i-1] < value implies all arr[0..i) < value (by sortedness)
      #|  arr[j] >= value implies all arr[j..len) >= value
      #|Termination: j - i decreases each iteration.
      #|Correctness at exit: arr[0..i) < value and arr[i..len) >= value.
    ),
  }
}

///|
test "iteration" {
  let arr : Array[Int] = [1, 3, 5, 7, 9]
  inspect(binary_search(arr, 5), content="Ok(2)")
  for i, v in arr {
    println("\{i}: \{v}")                    // i = index, v = value
  }
}
```

**Prefer functional `for`** over imperative. For trivial loops, use `for x in collection` — no reasoning needed.

#### Loop invariants (`where` clause)

Attaches machine-checkable invariants and human-readable reasoning:

```mbt nocheck
for ... {
  ...
} where {
  proof_invariant : <boolean_expr>,
  proof_invariant : <boolean_expr>,
  proof_reasoning : <string>
}
```

(The older `invariant:` / `reasoning:` keys are deprecated — `reasoning:` already
warns; use the `proof_`-prefixed names.)

Writing good invariants:
1. **Checkable** — use valid boolean expressions over loop variables.
2. **Boundary witnesses** — for "all elements in arr[0..i)" properties, check only boundary elements.
3. **Edge cases with `||`** — e.g. `i == 0 || arr[i-1] < value`.
4. **Reasoning covers three aspects** — Preservation (each `continue` maintains invariants), Termination (decreasing measure), Correctness (invariants at exit imply postcondition).

### Functional `loop` (MoonBit-specific)

Unlike `for`, `loop` pattern-matches on loop variables and uses `continue` with updated values. Great for tail-recursive-style algorithms:

```mbt check
///|
/// Pattern-match on a @list.List
fn sum_list(list : @list.List[Int]) -> Int {
  loop (list, 0) {
    (Empty, acc) => acc
    (More(x, tail=rest), acc) => continue (rest, x + acc)
  }
}

///|
/// Two-pointer search with loop
fn find_pair(arr : Array[Int], target : Int) -> (Int, Int)? {
  loop (0, arr.length() - 1) {
    (i, j) if i >= j => None
    (i, j) => {
      let sum = arr[i] + arr[j]
      if sum == target {
        Some((i, j))
      } else if sum < target {
        continue (i + 1, j)
      } else {
        continue (i, j - 1)
      }
    }
  }
}
```

**`loop` requires a payload.** For an infinite loop, write `for ;; { ... }` — `loop { ... }` without arguments is invalid, and `for { ... }` is not the infinite-loop form either.

### `while` returns a value

```mbt check
///|
test "while with break value" {
  let array = [1, 2, 3, 4, 5]
  let mut i = 0
  let target = 3
  let found : Int? = while i < array.length() {
    if array[i] == target {
      break Some(i)                          // exit with a value
    }
    i = i + 1
  } nobreak {
    None                                     // value when loop completes normally
  }
  assert_eq(found, Some(2))
}
```

The no-break block on `while` / functional `for` is spelled `nobreak { ... }`;
the old `else { ... }` spelling is deprecated (warns, `moon fmt` migrates it).

### Labelled loops

Use `label~:` before a loop and `break label~` / `continue label~` to target
that loop from a nested loop. Keep the trailing `~` on both the label
declaration and the labelled control-flow statement; `break label` is parsed as
breaking with the value `label`, not as a labelled break.

```mbt check
///|
test "labelled break" {
  let mut seen = 0
  outer~: while true {
    for x in [1, 2, 3] {
      seen = x
      if x == 2 {
        break outer~
      }
    }
  }
  assert_eq(seen, 2)
}
```

### Labelled blocks

A plain `{ ... }` block can carry a label too: `label~: { ... }` is an
expression, and `break label~ value` exits the block immediately with `value`
as its result (`break label~` with no value exits with `Unit`). The block's
last expression is the normal result; every `break label~` and the final
expression must agree on type. This is early-exit-with-value without a helper
function — like Rust's label-break-value or Zig's labelled blocks:

```mbt check
///|
fn absolute(n : Int) -> Int {
  result~: {
    if n < 0 {
      break result~ -n // early exit: -n becomes the block's value
    }
    n // normal exit: last expression
  }
}

///|
test "labelled block" {
  assert_eq(absolute(-5), 5)
  // the break may cross intervening loops:
  let found : Int? = search~: {
    for i in 0..<10 {
      for j in 0..<10 {
        if i * j == 12 {
          break search~ Some(i * 10 + j)
        }
      }
    }
    None
  }
  assert_eq(found, Some(26))
}
```

Rules:
- `continue label~` cannot target a block label — compile error 4112 ("Use
  `break label~` to exit this block"). `continue` is for loop labels only.
- A declared-but-never-broken block label warns (`unused_block_label`, 0037)
  — remove the label rather than suppressing the warning.
- As with labelled loops, keep the trailing `~` on both ends: `break label`
  without `~` is parsed as breaking with the *value* `label`.

## `defer` — scope-exit cleanup

MoonBit has `defer` (there is no `finally`). `defer expr` / `defer { ... }`
registers cleanup that runs when the enclosing scope exits — on normal exit
and when an error propagates. Multiple defers run in FILO order:

```mbt nocheck
fn with_raw_mode(term : Terminal) -> Unit raise {
  term.enter_raw_mode()
  defer term.leave_raw_mode()      // runs even if body raises
  defer { log.write_string("bye") } // block form; runs before the line above
  run_body(term)
}
```

Prefer `defer` over duplicating cleanup in both the success path and a `catch`
branch — for **sync** cleanup only. `defer` bodies cannot call async functions
(compile error: "cannot call async function in defer"); async cleanup needs
the two-path `catch`/normal split (factor it into a `with_*(async fn(x)
{ ... })` fixture when it recurs across tests) or `TaskGroup::add_defer`.

In `moonbitlang/async`, `defer` does run on cancellation; cancellation-safe
async cleanup (`@async.protect_from_cancel` and its refinements,
`TaskGroup::add_defer`) is covered in `async.md`.
