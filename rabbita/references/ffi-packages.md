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

Adding any **new** `extern "js"` body requires the user's explicit approval first — present which built-ins you checked and why they don't cover the need (see SKILL.md for the anti-patterns this gate exists to catch).

## Anti-patterns with built-in commands

- **Ignoring the returned `Cmd`/`Request`**: `@http.get("api/user") |> ignore` does nothing. Return the Cmd from update.
- **Storing a `Request` or `Cmd`** in a global, the Model, or any data structure. Construct commands fresh in update.
- **Embedding logic in the emit callback**: `expect_empty(r => emit(Status(r.is_none())))` hides a decision in a closure. Carry the raw payload (`emit.map(r => Deleted(r))`) and decide in update.
- **Wrapping a one-line request in a helper function** (`fn fetch_user(emit) -> Cmd { @http.get(...).expect_json(...) }`) — inline it at the use site. (Helpers that bundle several arguments from the model, as in multi-argument `@websocket.connect` calls, are fine.)
- **Awaiting a promise on a foreign async runtime inside a Cmd.** Since Rabbita moved onto `moonbitlang/async`, `@js.Promise` from `moonbit-community/rabbita/js` is a type alias of `@js_async.Promise`, so `.wait()` and `@js.Promise::from_async(...)` are the sanctioned way to bridge; anything that spins its own scheduler or event loop is not. (Pre-0.15 pins had a separate Rabbita runtime where mixing the two panicked — if the project pins one of those, keep everything on `@rabbita/js`.)

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
read once while constructing the initial model — in the component body, which
runs exactly once at mount — and reference via `model.foo`.

```moonbit
fn app() -> Val[Html] {
  let init = {
    origin: get_origin(),
    viewport_width: js_inner_width(),
    viewport_height: js_inner_height(),
    // ...
  }
  let (model, emit) = @rabbita.create_state(init, update~, subscriptions~)
  model.view(model => view(model, emit))
}

fn main {
  @rabbita.new(app).mount("app")
}
```

Then `update` and `view` read `model.origin`, `model.viewport_width`, etc.
(Use `create_state_with_init(init=emit => (model, cmd), update~)` when a
startup command must run as well; the old `App::with_init` is gone.)

**Changes over time** (viewport on resize, mouse position, visibility, time):
subscribe to the event and carry the payload through a message.

```moonbit
// subscriptions : (Model, Emit[Msg]) -> @sub.Sub
fn subscriptions(_model : Model, emit : Emit[Msg]) -> @sub.Sub {
  @sub.on_resize(emit.map(viewport => WindowResize(viewport)))
}

// Msg carries the payload
WindowResize(@common.Viewport)

// update reads from the payload, never from window.*
WindowResize(viewport) => (
  { ..model, viewport_width: viewport.width, viewport_height: viewport.height },
  @rabbita.none,
)
```

Either way, `update` and `view` never call an `extern "js"` that reads
external state. The only DOM reads happen in the component body (which runs
once at mount) or inside `Cmd` closures and subscription callbacks (which are
scheduled by the runtime, not called by update).

## Rule: snapshot live DOM collections at the extern boundary

`element.children` / `element.childNodes` / `getElementsBy*` are **live**
collections. Rabbita's own `@dom.Element::get_children` returns the live
`HTMLCollection` (typed as such since 0.16; older pins mistyped it as
`Array[Element]`), and `HTMLCollection::iter()` reads `item(index)` lazily
while you iterate. Mutating the DOM inside the loop shifts the collection under
the cursor:

```moonbit
// BROKEN: each remove shrinks the live collection; the cursor skips every
// other child, half of them survive, and the next re-render inherits the
// half-cleared DOM. (Older bindings typed as Array[Element] threw
// "removeChild: Argument 1 is not an object" instead.)
for child in parent.get_children() {
  parent.remove_child(child.as_node())
}
```

Fix: snapshot before mutating —

```moonbit
for child in parent.get_children().iter().to_array() {
  parent.remove_child(child.as_node())
}
```

or, in your own extern, `Array.from(element.children)` and return
`Array[@dom.Element]`.

A `firstChild`-drain loop is the other correct shape, but don't build it on
`@dom.Node::get_first_child` — that binding is typed plain `Node` while the DOM
returns `null` at the end, so it needs your own nullable extern too.

Treat any binding that returns a DOM collection as suspect until you've
confirmed it snapshots (`Array.from`, spread, `.iter().to_array()` before the
loop) rather than iterating the live object — and when writing your own,
always snapshot.

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
- [ ] JS promises bridged with `@js.Promise` (`moonbit-community/rabbita/js`, an alias of `@js_async.Promise` on 0.16) via `.wait()` / `Promise::from_async`; no hand-rolled scheduler
- [ ] Externs returning DOM collections snapshot with `Array.from(...)` — never hand back a live `HTMLCollection`/`NodeList` typed as `Array[T]`; callers of `get_children()` snapshot with `.iter().to_array()` before mutating
- [ ] DOM-bound widget lifecycle owned by a subscription (unload = dispose) rather than a user-callable `close` Cmd; keyed string-id registries only for non-DOM resources (websocket-style)

This makes it **impossible** for update to call side effects directly — the only public API returns `Cmd`.

## Command constructors reference

| Need | Constructor |
|------|------------|
| One-shot raw side effect (escape hatch) | `@cmd.custom_cmd(_ => ...)` |
| After DOM render | `@cmd.custom_cmd(kind=AfterRender, _ => ...)` |
| Multiple commands | `@rabbita.batch([cmd1, cmd2])` |
| Delayed command | `@rabbita.delay(cmd, ms)` |
| No-op | `@rabbita.none` |
| Startup command | `@rabbita.create_state_with_init(init=emit => (model, cmd), update~)` |
| Load-once resource | `@rabbita.create_resource(inject => @http.get(url).expect_json(inject))` → `Val[Status[T]]` |

(For async operations, see "Closing the loop" above. `raw_effect` is a
deprecated alias of `custom_cmd`; `App::with_init` no longer exists.)

`custom_cmd` builds a `LegacyEffect` on top of the `@cmd.Op` / `extenum
@cmd.Extension` machinery that the built-in packages use (`op.request(...)`
with `OpCont::Async` / `AfterLayout` / `Ready`). That machinery is
`#internal(experimental)`; app code stays on `custom_cmd` until it stabilises.

## Custom subscriptions

`@sub.custom_sub(key, scope, payload, loader)` is the subscription-side escape
hatch (0.16 signature):

- `key : String` identifies the subscription; `scope : Local | Global` decides
  whether it is shared across components.
- `payload : Error` carries the current tagger/config as a `suberror` value
  (`priv suberror MySub { Listen(Emit[Event]) }`), so the runtime can hand
  the *new* payload to a running subscription instead of tearing it down.
- `loader : SubLoader((payload, scheduler) -> RunningSub?)` starts the
  listener and returns `{ unload, update_tagger }`: `unload` removes the
  listener; `update_tagger` receives the next payload when `subscriptions`
  re-evaluates with the same key (`guard payload is Listen(next) else { return }`
  then swap the stored emit).
- Return `None` on `#cfg(not(target="js"))` builds.

Keep matching/deciding out of the loader: forward the raw event through the
emit and decide in update.
