---
name: rabbita
description: Use when writing or modifying update functions or views in Rabbita (Elm-architecture) MoonBit apps, creating FFI binding packages for Rabbita, designing Rabbita model types, debugging rendering/focus/scroll issues, or writing tests for Rabbita update handlers. Use when touching code that handles messages, modifies model, builds @html views, or interacts with JS FFI inside update.
---

# Rabbita

Baseline: **Rabbita 0.17.0** (checked against the published package source,
2026-11-10; moonc v0.10.20). Check the project's `moon.mod` pin. A `moon.work`
workspace resolves one Rabbita version for every member — per-module pins are
not a thing. Rabbita requires `moonbitlang/async` 0.22. Facts the compiler will
not tell you: `auto_complete?` / `Attrs::autocomplete` take a `String` token
list (`"off"`, `"current-password"`, ...), not an enum; `Attrs::attribute(key,
value)` is a public, unsanitized raw-attribute escape hatch; root-relative
`@http` URLs (`"/api/x"`) resolve against the origin, other relative URLs
against `document.baseURI`.

A Rabbita app is a tree of **components**: ordinary functions returning
`Val[Html]` that run once at mount to build an incremental graph. Inside a
component, state is created with:

- `create_pure_state(init, update~)` — `update : (Model, Msg) -> Model`
- `create_state(init, update~, subscriptions?)` — `update : (Model, Msg, Emit[Msg]) -> (Model, Cmd)`, `subscriptions : (Model, Emit[Msg]) -> @sub.Sub`
- `create_variable(init)` — returns a setter `Emit[(Model) -> Model]`
- `create_state_with_init(init=emit => (Model, Cmd), update~)` — startup command
- `create_state_with_input(input=val, init~, update~)` — child that reads a parent `Val`; `init : (Emit[Msg], Input) -> (Model, Cmd)`, `update : (Model, Input, Msg, Emit[Msg]) -> (Model, Cmd)`

Each returns `(Val[Model], Emit[Msg])`. For a single-state app,
`@rabbita.elmish(model~, view~, update~, subscriptions?)` wraps `create_state` +
`new` and returns the `App`. **`Model` must implement `Eq`**: an
equal result stops propagation, so derive `Eq` and keep the model immutable.

**A component body runs exactly once, at mount**, and a `Val` input is a value
read while a callback runs, not a signal. Read "Components and their inputs"
in `references/view-rendering.md` before deciding where a piece of state lives.

**`update` must be a pure function.** It returns a new model and commands
describing side effects — it never executes side effects directly. This purity
is enforced through effect-package design, model structure, and testing.

`Emit[Msg]` is a callable `(Msg) -> Cmd`: `emit(Inc)` yields a Cmd (usable directly as `on_click=emit(Inc)`), and `emit.map(payload => Msg(payload))` adapts it to `Emit[Payload]` for subsystem APIs. Keep emit lambdas short: `x => emit(UserMsg(x))`.

> Removed outright, with no shim or hint: `App::with_init(cmd)` (use
> `create_state_with_init`) and `App::with_route(url_changed=...)` (use the
> `@sub.on_url_changed` / `@sub.on_url_request` subscriptions).

## The Three Rules

```
1. update and view MUST be pure — no side effects, only return (Model, Cmd) / Html
2. Side effects go through Cmd-returning APIs — built-in packages first;
   any hand-written FFI package exposes ONLY Cmd-returning functions
3. Model holds data only, with Eq — enums to eliminate impossible states;
   never Cmd, Msg, Request, or callbacks; collections immutable
```

**Impurity includes reads, not just writes.** Any `extern "js"` call that reads browser global state (`window.innerWidth`, `window.location.origin`, `Date.now()`, `localStorage.getItem`) inside update or view silently breaks idempotence. Values stable for the app's lifetime → read once in the component body (it runs once at mount) or in `main` and store on `Model`; values that change over time → subscribe (`@sub.on_resize`, `@sub.every`, ...) and carry the payload through a `Msg`. See `references/ffi-packages.md` for both patterns with code.

## Use built-in effect packages before writing FFI

Rabbita ships Cmd/Sub-returning packages for most browser effects: `@http`, `@websocket`, `@clipboard`, `@nav`, `@dialog`, `@url`, and `@sub` (resize, key down/up, mouse move, scroll, visibility, animation frame, timer, URL changes). `@rabbita.create_resource` covers load-once data. Check these before hand-writing any `extern "js"`. There is no storage package (no `@indexeddb`, no `localStorage` wrapper) — persistence is a legitimate FFI package, still under the approval rule below.

Avoid the escape hatches — `@cmd.custom_cmd`, `@sub.custom_sub`, `@cmd.effect`, `@cmd.attempt`, `@html.Attrs`, `@dom`, `trait Scheduler` — unless you are binding a JS library the built-ins genuinely don't cover (then follow `references/ffi-packages.md`). The `@cmd.Op` / `extenum @cmd.Extension` machinery the built-ins use is `#internal(experimental)`; app code stays on `custom_cmd`.

**Writing new inline JS requires the user's explicit approval.** Never add a new `extern "js"` body without first asking the user, naming the built-ins you checked and why they fall short. Inline JS is where anti-patterns enter the codebase unnoticed — real cases caught in review:

- Replacing a working built-in subscription (`@sub.on_key_down`) with a raw `document.addEventListener` during a component refactor.
- Rendering `data-*` marker attributes and watching them with a `MutationObserver` to signal state changes between components — using the DOM as a message bus. State flows through `Msg`/`Emit`/component `Input`, never out through the DOM and back.
- Deciding business logic inside the JS string — shortcut matching, platform detection (`navigator.platform`), URL allowlists, close-on-outside-click via `closest()`. Carry the raw event through a `Msg` and decide in update.

Each of these compiled and worked, which is exactly why they need a human gate. Editing an existing extern in an established FFI binding package does not need re-approval.

Routing: map the URL into the model with `@html.a`, `@sub.on_url_changed`, and `@sub.on_url_request` — do not encode a navigation state machine in update.

## Route to references by task

Load the reference matching your current work BEFORE writing code:

| Task | Read |
|---|---|
| Using built-in effect packages, or binding a new JS library (dummy constructors, private externs, Cmd-returning API, wiring JS events back into the update loop via `Emit`, live DOM collection snapshotting, command constructor reference, package checklist) | `references/ffi-packages.md` |
| Designing or refactoring `Model` types (`Eq` requirement, immutable collections, state enums, spotting hidden state machines, what must never live in a model) | `references/model-design.md` |
| Writing tests for update handlers (idempotence, dummy object trap, state transitions, test helpers) | `references/testing.md` |
| Writing or debugging views (positional vs keyed children, focus loss and focusing inserted inputs, view totality, what reruns on a change, components and their `Val` inputs, DOM identity across components, event handlers and render-time capture, model-driven menus, `@html` element surface, void elements, auto-scroll, embedding foreign DOM widgets) | `references/view-rendering.md` |
| Using `moonbit-community/rui` components (`Html` vs `Val[Html]` APIs, native dialogs via `@dialog.show`, one controlled menu per surface, `@rui.theme` and `--rui-*` tokens, when to copy component source) | `references/rui.md` |

## Message Design: Namespace by Subsystem

Each subsystem package owns its own `Msg` enum (built-ins already do: `@websocket.Event`, `@url.UrlRequest`, ...). The root `Msg` wraps them by channel. This keeps the root enum from ballooning into 200 variants and makes ownership obvious.

```moonbit
// xterm/commands.mbt — xterm subsystem owns its messages
pub(all) enum Msg {
  Mounted(Terminal)
  Data(String)
  Resize(cols~ : Int, rows~ : Int)
}

// main/client.mbt — root Msg wraps subsystem messages
enum Msg {
  Xterm(@xterm.Msg)
  Socket(@websocket.Event)
  // ... plus top-level UI messages
  ToggleTerminal
}
```

Wire subsystem emits at the call site with `emit.map`: `@xterm.mount("terminal", emit.map(m => Xterm(m)))`, `on_event=emit.map(e => Socket(e))`.

When a subsystem grows beyond ~5 messages or is likely to be reused, extract it into its own package with its own `Msg`. When it also owns local state, make it a child component (`() -> Val[Html]`) and pass parent data as `Val` inputs and callbacks as `Cmd` / `Emit` parameters.

Label every non-obvious `Msg` payload — `AgentProgress(run_id~ : Int, Event)`, not a bare positional `Int`. Name FFI/subsystem packages by domain (`alert`, `bridge`, `xterm`), never with an `_ffi` suffix.

## View & Rendering Rules (see `references/view-rendering.md`)

1. `Array[Html]` children diff **by index**; `Map[String, Html]` children diff **by key**. A conditional sibling in an array list shifts every later index and rebuilds focus-holding nodes (inputs/textareas) — render it after them, or give the list stable keys. Lists that insert/remove/reorder use keyed children; items that own state use `Val::assoc_by`.
2. `view` must be **total**: one raise inside a render callback stops rendering. Guard any parser fed partial/streaming input.
3. A render callback reruns whenever one of its `Val` inputs changes, and it rebuilds all the `Html` it returns — so derive narrower `Val`s (`model.map(m => m.field).view(...)`), wrap expensive subtrees in `@html.memo(inputs, render)` (there is no `@html.lazy`), and cache expensive derivations (parsed ASTs, layouts) in the Model at message time, never in view.
4. Void elements (`hr`, `br`, `img`, `input`) take **zero** children — no trailing `@html.nothing`.
5. `on_click` exists only on `div`, `button`, `li`, `ul` (not `a`/`span`); check the `.mbti`. Clickable text is a styled `button`. Since `on_click` takes an erased `Cmd`, subpackages accept `(payload) -> Cmd` callbacks instead of importing the root `Msg`.
6. `on_click` does **not** stop propagation — a clickable nested inside a clickable ancestor fires both handlers. Use the `@html.Attrs` event lambda with `event.stop_propagation()` (a legitimate escape-hatch use) or restructure to avoid nesting.
7. Event handlers **emit unconditionally**; the guard lives in update. A closure that branches on a value captured at render time (`if valid { emit(Submit) }`) sees the last painted frame, so type-then-Enter inside one frame does nothing.
8. Component identity is DOM identity only when the container is keyed: a positional slot holding the same tag is patched in place across two different components. Key the container, and resolve DOM nodes after render, never inside a subscription loader.
9. A menu whose visibility follows the model is `position: fixed` + CSS anchor positioning inside a size container, not the top layer (`popover`). Reserve the top layer for click-opened menus whose toggle itself calls `show()`.
10. SSR/native builds: a package that only makes sense in a browser declares `supported_targets = "js"` instead of carrying native stubs. In a package that really renders on native, gate DOM-backed code with `#cfg(target="js")`; a native counterpart is acceptable only where doing nothing is the correct server behavior (an effect Cmd that has no meaning during SSR), never as a placeholder for a value. `@rabbita.perform` / `attempt` / `effect` are `#cfg(target="js")` — packages using them must declare js-only targets (`delay`, `batch`, `custom_cmd` compile on every target).

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Hand-written FFI for http/websocket/clipboard/navigation/dialogs | Use the built-in package (`@http`, `@websocket`, ...) |
| `pub fn Terminal::write(...)` in FFI package | Make method `fn` (not `pub`); expose `pub fn write(...) -> Cmd` |
| `term.dispose()` in update | Return `@xterm.dispose(term)` as Cmd |
| `js_inner_width()` / `get_origin()` / `Date.now()` in update or view | Read once in the component body or `main`, store on Model; or subscribe and carry via Msg |
| Storing `Cmd`, `Msg`, `@http.Request`, or callbacks in Model (or globals) | Model holds plain data; construct commands fresh in update |
| Ignoring a returned `Cmd` / `Request` (`... \|> ignore`) | Return it from update (batch with `@rabbita.batch` if needed) |
| Business logic inside emit callbacks (`emit.map(s => Msg(s.has_prefix("x")))`) | Carry the raw payload in the Msg; decide in update |
| `Option` + `Bool` for lifecycle state | Replace with enum |
| Mutable `Array[T]` / `Map` mutated in place in model | Use `@immut/*` (e.g. `@vector.Vector[T]`); never mutate a model collection in place — `Eq` cannot see in-place changes |
| `struct Model` without `Eq` passed to `create_state` | `#derive(Eq)`; for FFI-handle fields write `impl Eq` by identity/generation (see `references/model-design.md`) |
| FFI type without `dummy()` | Add `pub fn T::dummy() -> T` using `@js.Object::new().to_value()` |
| New message handler without purity test | Add idempotence + dummy trap tests |
| `Dispatch`, `cell`/`simple_cell`/`static_cell`, `App::with_init`, `@cmd.raw_effect` in new code | `Emit`, a component with `create_state`/`create_pure_state`/`Val::constant`, `create_state_with_init`, `@cmd.custom_cmd` |
| `update` written as `(emit, msg, model) -> (cmd, model)` | `(model, msg, emit) -> (model, cmd)` — the 0.16 `create_state` shape |
| `@cmd.custom_cmd` inline in update | Use a built-in package, or move into an FFI package as a named Cmd function |
| New `extern "js"` written without asking the user | Stop; propose it with the built-ins you checked and wait for approval |
| Plain-value component parameter that the parent expects to update; a stateful component wrapped around each list row; a component expected to react when only its input changed | See "Components and their inputs" in `references/view-rendering.md` — pass a `Val`, keep one controlled instance per list, forward a `Msg` from the parent |
| `@rui.context_menu` / `dropdown_menu` wrapped around each row, kept fresh by a hand-written `switch_by(by=revision)` | One controlled rui menu at surface level: the model holds `(target, anchor)`, rows emit target keys, entries resolve from the current model (see `references/rui.md`) |
| Hand-rolled modal, menu, popover, or focus trap in an app that already depends on rui | Use the rui component; copy its source only when the DOM or interaction model must differ |
| Relying on `autofocus=true` for an input inserted in response to a click | The clicked control already holds focus, so the browser skips autofocus; return an after-render focus Cmd from the update branch that inserts the input |
| Handler closure deciding with a render-time `Bool` before emitting (`Emit(key => if valid { ... })`) | Emit unconditionally (`emit.map(key => KeyDown(key))`); update reads current state |
| `data-*` marker + `MutationObserver` so a component notices its own input changed | Deliver the change through the component's `Input`/`Msg`; state never round-trips through the DOM |
| Raw `document.addEventListener` for keys/clicks in a sub loader | `@sub.on_key_down` / `on_key_up` / `on_mouse_move`, or element `on_mousedown=` (there is no global mouse-down sub); keep the match-and-decide logic in update |
| Trailing `@html.nothing` on `hr`/`br`/`img`/`input` | Void elements take zero children |
| Parsing/deriving expensive data inside `view` | Cache it in the Model at message time; view reads the cache |
| One giant `model.view(...)` re-rendering everything on each change | Split into narrower `Val`s / child components; `@html.memo` for expensive static subtrees |
| Mutable `Ref` flag inside a sub loader / FFI closure to mute or filter events | Track connection identity (generation/id) in the Model and drop stale events in update — or fix the effect package itself |
| Fire-and-forget Cmd whose completion a later Msg depends on | Model the pending state as an enum and gate the dependent transition on the completion Msg |
| `for child in parent.get_children() { parent.remove_child(...) }` | `get_children()` returns the **live** `HTMLCollection` and its `iter()` walks it lazily by index; removals shrink it under the cursor and skip children. Snapshot first: `parent.get_children().iter().to_array()` (see `references/ffi-packages.md`) |

## Red Flags in Code Review

- Hand-rolled `extern "js"` for something a built-in package covers
- New inline JS the user never approved (see the approval rule above)
- `MutationObserver` watching attributes the app itself renders (DOM as message bus)
- Global capture-phase listener calling `preventDefault`/`stopPropagation` behind the renderer's back
- Shortcut matching, platform detection, or URL filtering inside a JS string instead of update
- FFI package exposes `pub fn` that returns `Unit` (should return `Cmd`)
- FFI type has no `dummy()` constructor
- `Cmd`, `Msg`, or `Request` values stored in a model field or global
- Mutable collection in a model field mutated in place
- `model.foo : T?` paired with `model.foo_loading : Bool` or `model.foo_visible : Bool`
- Any method call on a JS FFI object inside update
- New message handler without idempotence test
- Update branch that calls a function then returns `(model, @rabbita.none)`
- Conditional sibling rendered before a focus-holding element in an `Array` child list (index shift = focus loss); a dynamic list rendered as `Array[Html]` instead of keyed `Map[String, Html]`
- A raise-capable call inside `view` without a catch-and-fallback at the boundary
- A component taking plain parameters the parent recomputes, or a stateful component instantiated per list row
- A subscription loader that calls `get_element_by_id` (or any DOM lookup) synchronously
- A unit or e2e test asserting Rabbita's own behavior: DOM node identity, `isConnected`, diff output
- A loop that mutates the DOM children it is iterating (`get_children()` / any live-collection binding + `remove_child`/`append_child` in the body)
