# Effect Packages: Built-ins First, Then FFI

## Step 0: Check the built-in packages

Rabbita already ships Cmd/Sub-returning wrappers for most browser effects. Use them instead of writing `extern "js"`:

| Need | Package |
|------|---------|
| HTTP requests | `@http` — `@http.get("api/user").expect_json(emit.map(r => UserLoaded(r)))`; `post/put/patch` take a body via `.with_json/with_text/...`; results arrive as `Emit[Result[T, Error]]` |
| WebSocket | `@websocket` — connections are keyed by a **string id**, no handle in the model: `@websocket.connect(id, url, on_event=emit.map(e => Socket(e)))`, `send(id, payload)`, `close(id)`, or subscription-style `@websocket.listen(...)` |
| Clipboard | `@clipboard` |
| Navigation / URL | `@nav`, `@url`, `@sub.on_url_changed`, `@sub.on_url_request`, `@html.a` |
| Dialogs | `@dialog` |
| IndexedDB storage | `@indexeddb` |
| Window/global events | `@sub.on_resize`, `on_key_down/up`, `on_mouse_move`, `on_scroll`, `on_visibility_change`, `on_animation_frame`, `every` (timer) |

Escape hatches — `@cmd.custom_cmd`, `@sub.custom_sub`, `@cmd.effect`, `@cmd.attempt`, `@html.Attrs`, `@dom`, `trait Scheduler` — are for binding JS libraries the built-ins don't cover (an editor widget, a charting library, xterm.js, ...). Only then write an FFI package, following the rules below.

## Anti-patterns with built-in commands

- **Ignoring the returned `Cmd`/`Request`**: `@http.get("api/user") |> ignore` does nothing. Return the Cmd from update.
- **Storing a `Request` or `Cmd`** in a global, the Model, or any data structure. Construct commands fresh in update.
- **Embedding logic in the emit callback**: `expect_empty(r => emit(Status(r.is_none())))` hides a decision in a closure. Carry the raw payload (`emit.map(r => Deleted(r))`) and decide in update.
- **Wrapping a one-line request in a helper function** (`fn fetch_user(emit) -> Cmd { @http.get(...).expect_json(...) }`) — inline it at the use site. (Helpers that bundle several arguments from the model, as in multi-argument `@websocket.connect` calls, are fine.)

# Hand-Written FFI Package Design

Every FFI package wrapping a JS object follows this structure:

```
xterm/
  xterm.mbt       # Type + raw extern "js" bindings (private to package)
  commands.mbt     # Public API: all operations return Cmd
```

## Rule: Every type MUST have a dummy constructor for testing

```moonbit
// xterm/xterm.mbt
pub struct Terminal(@js.Value)

/// Dummy for testing. Calls to any method will throw,
/// proving update never invokes them directly.
pub fn Terminal::dummy() -> Terminal {
  Terminal(@js.Object::new().inner())
}
```

## Rule: Every side-effectful operation MUST return Cmd

The raw `extern "js"` bindings are private (`fn`, not `pub fn`). The public API consists only of `Cmd`-returning functions in `commands.mbt`:

```moonbit
// xterm/xterm.mbt — PRIVATE raw bindings
extern "js" fn terminal_write(term : @js.Value, data : String) -> Unit = ...
extern "js" fn terminal_fit(term : @js.Value) -> Unit = ...
extern "js" fn terminal_dispose(term : @js.Value) -> Unit = ...

// Private method wrappers (used only inside the package)
fn Terminal::write(self : Terminal, data : String) -> Unit {
  terminal_write(self.0, data)
}
```

```moonbit
// xterm/commands.mbt — PUBLIC Cmd-returning API
pub fn write(term : Terminal, data : String) -> Cmd {
  @cmd.custom_cmd(_ => term.write(data))
}

pub fn fit(term : Terminal) -> Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => term.fit())
}

pub fn dispose(term : Terminal) -> Cmd {
  @cmd.custom_cmd(_ => term.dispose())
}

pub fn mount(container_id : String, emit : Emit[Msg]) -> Cmd {
  @cmd.custom_cmd(kind=AfterRender, scheduler => {
    // ... create terminal, wire events, emit Mounted
  })
}
```

## Rule: DOM reads and global-state reads are impurity too

The rules above cover method calls on FFI handles (`term.write`).
Equally impure: **any `extern "js"` function that reads browser global state
from inside `update` or `view`** — `window.innerWidth`, `window.location.origin`,
`Date.now()`, `localStorage.getItem`, etc. These look like plain function calls,
but each one reads mutable external state, so running the same handler twice
on the same model can produce different results. Idempotence is silently broken.

Two fix patterns, depending on how the value changes:

**Stable for the app's lifetime** (origin, initial viewport, locale, build version):
read once in `main` while constructing the initial model, reference via `model.foo`.

```moonbit
fn main {
  let app = @rabbita.cell(
    model={
      origin: get_origin(),
      viewport_width: js_inner_width(),
      viewport_height: js_inner_height(),
      // ...
    },
    update~, view~, subscriptions~,
  )
  @rabbita.new(app).mount("app")
}
```

Then `update` and `view` read `model.origin`, `model.viewport_width`, etc.
(Use `cell_with_emit` instead of `cell` only when you need the `Emit` outside
the cell; use `App::with_init(cmd)` to run startup commands.)

**Changes over time** (viewport on resize, mouse position, visibility, time):
subscribe to the event and carry the payload through a message.

```moonbit
// subscriptions : (Emit[Msg], Model) -> @sub.Sub
fn subscriptions(emit : Emit[Msg], _model : Model) -> @sub.Sub {
  @sub.on_resize(emit.map(viewport => WindowResize(viewport)))
}

// Msg carries the payload
WindowResize(@common.Viewport)

// update reads from the payload, never from window.*
WindowResize(viewport) => (
  @rabbita.none,
  { ..model, viewport_width: viewport.width, viewport_height: viewport.height },
)
```

Either way, `update` and `view` never call an `extern "js"` that reads
external state. The only DOM reads happen in `main` (which runs once)
or inside `Cmd` closures and subscription callbacks (which are scheduled by
the runtime, not called by update).

## Closing the loop: commands emit messages back

Commands run side effects, but they also feed results back into the update loop via the scheduler. `emit(msg)` produces a Cmd; `scheduler.add(cmd)` queues it. This is how async results become messages:

```moonbit
// xterm/commands.mbt
pub fn mount(container_id : String, emit : Emit[Msg]) -> Cmd {
  @cmd.custom_cmd(kind=AfterRender, scheduler => {
    let term = create_terminal_and_attach(container_id)
    // Wire JS events → messages. Each keystroke becomes a Data message.
    terminal_on_data(term.0, data => scheduler.add(emit(Data(data))))
    // Emit Mounted so update can store the handle in the model.
    scheduler.add(emit(Mounted(term)))
  })
}
```

The `emit : Emit[Msg]` parameter carries this subsystem's messages. The caller adapts its root emit at the call site with `Emit::map`:

```moonbit
// In update:
@xterm.mount("terminal", emit.map(m => Xterm(m)))
```

This is the full loop: `Msg → update → Cmd → scheduler runs side effect → scheduler.add(emit(new Msg)) → update → ...`. Commands are never dead-ends — they either complete silently or feed new messages back.

For simple async with no subsystem-specific messages, use the direct helpers (also re-exported as `@rabbita.perform` / `attempt` / `effect`):

| Use case | Helper |
|----------|--------|
| Async operation, success becomes a `Msg` | `@cmd.perform(x => emit(OnSuccess(x)), async fn() noraise { ... })` |
| Async operation, result becomes a `Msg` with error | `@cmd.attempt(r => emit(OnResult(r)), async fn() raise { ... })` |
| Fire-and-forget async effect | `@cmd.effect(async fn() noraise { ... })` |

## Complete FFI package checklist

For every new FFI package:

- [ ] The built-in packages genuinely don't cover this (checked `@http`, `@websocket`, `@clipboard`, `@nav`, `@dialog`, `@indexeddb`, `@sub`)
- [ ] `pub struct FooHandle(@js.Value)` — opaque wrapper
- [ ] `pub fn FooHandle::dummy() -> FooHandle` — empty JS object for testing
- [ ] All `extern "js"` functions are **not** `pub`
- [ ] All public operations return `Cmd`, never `Unit`
- [ ] Method wrappers (`fn FooHandle::method`) are **not** `pub`
- [ ] Public API takes `Emit[Msg]` for event wiring; callers adapt with `emit.map`

This makes it **impossible** for update to call side effects directly — the only public API returns `Cmd`.

## Command constructors reference

| Need | Constructor |
|------|------------|
| One-shot raw side effect (escape hatch) | `@cmd.custom_cmd(_ => ...)` |
| After DOM render | `@cmd.custom_cmd(kind=AfterRender, _ => ...)` |
| Multiple commands | `@rabbita.batch([cmd1, cmd2])` |
| Delayed command | `@rabbita.delay(cmd, ms)` |
| No-op | `@rabbita.none` |
| Startup command | `@rabbita.new(app).with_init(cmd)` |

(For async operations, see "Closing the loop" above. `raw_effect` is a deprecated alias of `custom_cmd`.)
