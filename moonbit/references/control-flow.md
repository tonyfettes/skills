# MoonBit Control Flow

Expressions-as-values, range/functional `for` loops, the functional `loop`, `while` as an expression, and labelled loops. Split out of `language.md`.

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

### Functional `for` loop

```mbt check
///|
pub fn binary_search(arr : ArrayView[Int], value : Int) -> Result[Int, Int] {
  let len = arr.length()
  // for: initial state; [predicate]; [post-update] {
  //   body — `continue` updates state
  // } else { exit block }
  for i = 0, j = len; i < j; {
    let h = i + (j - i) / 2
    if arr[h] < value {
      continue h + 1, j
    } else {
      continue i, h
    }
  } else {
    if i < len && arr[i] == value { Ok(i) } else { Err(i) }
  } where {
    invariant: 0 <= i && i <= j && j <= len,
    invariant: i == 0 || arr[i - 1] < value,
    invariant: j == len || arr[j] >= value,
    reasoning: (
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
  invariant : <boolean_expr>,
  invariant : <boolean_expr>,
  reasoning : <string>
}
```

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
  } else {
    None                                     // value when loop completes normally
  }
  assert_eq(found, Some(2))
}
```

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
branch.

In `moonbitlang/async`, cancellation is delivered as a raised error at
suspension points, so `defer`/`catch` blocks do run on cancellation — but any
**async operation inside the cleanup** is itself cancelled immediately while
the task is being cancelled. Must-complete async cleanup needs
`@async.protect_from_cancel` (sparingly — it breaks `with_timeout`; pair with a
hard timeout) or `TaskGroup::add_defer` with the same protection inside.
