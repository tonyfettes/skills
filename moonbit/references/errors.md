# MoonBit Error Handling (Checked Errors)

Declaring and raising `suberror`s, `raise`/`catch`/`noraise`, error polymorphism (`raise?`), the `Error` bound on generics, and `try` block inference. Split out of `language.md`.

## Error handling (checked errors)

MoonBit uses checked error-throwing, not unchecked exceptions. All errors are subtypes of `Error`; declare custom types with `suberror`. Checked errors are tracked in function signatures, not marked at every call site — a function that may raise declares `raise` or `raise SomeError`. Errors propagate by default — **do NOT add `try`** for functions that raise (unlike Swift). Use:
- Plain call inside a `raise` function — propagates automatically.
- `expr catch { ... }` or `try { } catch { } [noraise { }]` — handle explicitly.
- `try! expr` — abort if it raises.

Do not use the legacy `function_name!(...)` / `function_name(...)?` syntax for new code. (`try?`, which converts to `Result[_, _]`, is being deprecated — prefer `try ... catch ... noraise` instead.)

```mbt check
///|
suberror ValueError {
  ValueError(String)
}

///|
struct Position(Int, Int) derive(ToJson, Debug, Eq)

///|
pub(all) suberror ParseError {
  InvalidChar(pos~ : Position, Char)
  InvalidEof(pos~ : Position)
  InvalidNumber(pos~ : Position, String)
  InvalidIdentEscape(pos~ : Position)
} derive(Eq, ToJson, Debug)

///|
fn parse_int(s : String, position~ : Position) -> Int raise ParseError {
  if s is "" {
    raise ParseError::InvalidEof(pos=position)
  }
  ...
}

///|
/// Just `raise` (no type) — don't track specific error type
fn div(x : Int, y : Int) -> Int raise {
  if y is 0 { fail("Division by zero") }
  x / y
}

///|
test "inspect raise function" {
  // Expected-failure shape: handle in `catch`, fail explicitly in `noraise`.
  try div(1, 0) catch {
    Failure(msg) => assert_true(msg.contains("Division by zero"))
    _ => fail("unexpected error")           // catch must be exhaustive over Error
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
/// Errors propagate automatically — no `try` needed
fn use_parse(position~ : Position) -> Int raise ParseError {
  let x = parse_int("123", position~)
  x * 2
}

///|
/// Convert to a Result by catching explicitly (replaces the deprecated `try?`)
fn safe_parse(s : String, position~ : Position) -> Result[Int, ParseError] {
  try parse_int(s, position~) catch {
    err => Err(err)
  } noraise {                                        // noraise block runs on success
    v => Ok(v)
  }
}

///|
/// try-catch with specific patterns
fn handle_parse(s : String, position~ : Position) -> Int {
  try parse_int(s, position~) catch {
    ParseError::InvalidEof(pos=_) => {
      println("Parse failed: InvalidEof")
      -1
    }
    _ => 2
  }
}
```

All `async` functions can raise errors without explicitly stating `raise`.

### Error polymorphism: `raise?` and `noraise`

A higher-order function whose own raising depends on its callback's raising must use `raise?`. The compiler resolves `raise?` to `raise` or `noraise` at each call site based on the callback type:

```mbt nocheck
fn[T] map(arr : Array[T], f : (T) -> T raise?) -> Array[T] raise? {
  let res = []
  for x in arr { res.push(f(x)) }
  res
}

fn pure(arr : Array[Int]) -> Array[Int] noraise {
  map(arr, x => x + 1)              // f is noraise → map call site is noraise
}

fn fallible(arr : Array[Int]) -> Array[Int] raise {
  map(arr, x => if x < 0 { fail("neg") } else { x })   // f raises → map call site raises
}
```

Without `raise?`, `map` would unconditionally appear to raise, polluting all callers. Use `raise?` whenever a function's raising is purely "as-raising-as my callback".

`noraise` makes the no-raise contract explicit on a signature. You'll see it most often on `async` functions (which otherwise raise implicitly):

```mbt nocheck
async fn pure_async() -> Int noraise { 42 }
```

### `Error` bound on generics

To write a function generic in the *concrete* error type (not just `Error`), bind a type parameter with `: Error`:

```mbt nocheck
fn[T, E : Error] unwrap_or_error(r : Result[T, E]) -> T raise E {
  match r {
    Ok(x)  => x
    Err(e) => raise e
  }
}
```

This preserves the specific error type at call sites — better than the catch-all `raise` (which is `raise Error`) when callers want to handle one variant.

### `try` block error inference

Inside a `try` block, multiple raise types collapse to `Error`. The handler must use `_` to catch all variants and re-raise unhandled ones:

```mbt nocheck
try {
  f1()                                // raise E1
  f2()                                // raise E2
} catch {
  E1(_) => ...
  E2    => ...
  e     => raise e                    // re-raise anything else
}
```
