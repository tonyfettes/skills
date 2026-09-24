# Testing Update Handlers

**Every update handler MUST have tests. Every test MUST verify purity.**

Keep `update` a top-level function of shape
`(Model, Msg, Emit[Msg]) -> (Model, Cmd)` and pass it as `update~` to
`create_state` inside the component; an inline closure cannot be called from a
test. (Pre-0.16 code used `(Emit, Msg, Model) -> (Cmd, Model)`; the examples
below use the 0.16 order.)

Purity means two things — both must be tested:

1. **Idempotence**: calling update twice on the same input produces the same model output
2. **No side effects**: update never calls FFI methods directly

## Test 1: Idempotence (REQUIRED for every message handler)

A pure function called twice with the same input MUST produce the same output. This is the most fundamental test — if this fails, update has hidden state or side effects.

```moonbit
test "update is pure: ToggleTerminal is idempotent" {
  let model = { ..test_model(), term_state: Open(@xterm.Terminal::dummy()) }
  let emit = test_emit()
  let (result1, _) = update(model, ToggleTerminal, emit)
  let (result2, _) = update(model, ToggleTerminal, emit)
  // Same input, same output — always.
  // Plain-data fields: two computed values → @debug.assert_eq (per the moonbit skill).
  @debug.assert_eq(result1.terminal_height, result2.terminal_height)
  // FFI-handle-bearing state (@js.Value has no meaningful Eq — don't derive Eq
  // just for tests): assert the shape with patterns instead.
  assert_true(result1.term_state is Hidden(_) && result2.term_state is Hidden(_))
}
```

**Do this for every message handler that touches FFI objects.** Compare every field the handler modifies — plain data via `@debug.assert_eq`, handle-bearing enums via `is` patterns.

## Test 2: Dummy object trap (REQUIRED for handlers touching FFI objects)

Use `dummy()` — an empty JS object with no methods. If update calls any method directly, JS throws. If update only captures calls inside Cmd closures, the closures are never executed during the test — so it passes.

```moonbit
test "update is pure: terminal messages produce no direct side effects" {
  let term = @xterm.Terminal::dummy()
  let emit = test_emit()
  let base = { ..test_model(), term_state: Open(term) }
  // Every one of these would throw if update called a method directly:
  let (_, _) = update(base, ToggleTerminal, emit)
  let (_, _) = update(base, Xterm(@xterm.Resize(cols=80, rows=24)), emit)
  let (_, _) = update(base, DragEnd, emit)
}
```

## Test 3: State transitions (REQUIRED for enum-based state)

Test every edge in the state machine:

```moonbit
test "ToggleTerminal transitions" {
  let term = @xterm.Terminal::dummy()
  let emit = test_emit()
  // Closed -> Mounting
  let (m, _) = update({ ..test_model(), term_state: Closed }, ToggleTerminal, emit)
  assert_true(m.term_state is Mounting)
  // Open -> Hidden
  let (m, _) = update({ ..test_model(), term_state: Open(term) }, ToggleTerminal, emit)
  assert_true(m.term_state is Hidden(_))
  // Hidden -> Open
  let (m, _) = update({ ..test_model(), term_state: Hidden(term) }, ToggleTerminal, emit)
  assert_true(m.term_state is Open(_))
  // Mounting -> Mounting (no-op)
  let (m, _) = update({ ..test_model(), term_state: Mounting }, ToggleTerminal, emit)
  assert_true(m.term_state is Mounting)
}
```

## Test helpers

```moonbit
fn test_model() -> Model {
  // Safe defaults. Use Closed/Idle for FFI-backed or connection state.
  { page: Login, term_state: Closed, socket_status: Idle, ... }
}

fn test_emit() -> Emit[Msg] {
  Emit(_msg => @rabbita.none)
}
```

(`Emit[Msg]` is `pub(all) struct Emit[Msg]((Msg) -> Cmd)`, so it can be
constructed directly. `Dispatch` is the deprecated old name.)

## What NOT to test in unit tests

- Commands. `Cmd` implements `Debug` on 0.16 (`debug_inspect(cmd)` prints
  built-in commands such as `ClipboardCopy(Text("hello"))` and batches), but
  that impl is `#internal(experimental)` and a `custom_cmd` closure prints as
  omitted — assert the model, not the command.
- View functions (need real DOM; the SSR `App::render` is
  `#cfg(not(target="js"))`, so it is unavailable in js test builds)
- Subscriptions (need runtime)

Focus tests on: **model output**, **idempotence**, and **no-throw with dummies**.
