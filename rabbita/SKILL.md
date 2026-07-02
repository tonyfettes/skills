---
name: rabbita
description: Use when writing or modifying update functions or views in Rabbita (Elm-architecture) MoonBit apps, creating FFI binding packages for Rabbita, designing Rabbita model types, debugging rendering/focus/scroll issues, or writing tests for Rabbita update handlers. Use when touching code that handles messages, modifies model, builds @html views, or interacts with JS FFI inside update.
---

# Rabbita

In Rabbita's Elm architecture, **`update` must be a pure function**: `(Emit[Msg], Msg, Model) -> (Cmd, Model)`. It returns a new model and commands describing side effects — it never executes side effects directly. This purity is enforced through effect-package design, model structure, and testing.

`Emit[Msg]` is a callable `(Msg) -> Cmd`: `emit(Inc)` yields a Cmd (usable directly as `on_click=emit(Inc)`), and `emit.map(payload => Msg(payload))` adapts it to `Emit[Payload]` for subsystem APIs. Keep emit lambdas short: `x => emit(UserMsg(x))`.

> Deprecated names you may see in old code: `Dispatch[Msg]` (now `Emit`), `cell_with_dispatch` (now `cell` / `cell_with_emit`), `@cmd.raw_effect` (now `@cmd.custom_cmd`), `App::with_route(url_changed=...)` (now `@sub.on_url_changed` / `@sub.on_url_request` subscriptions). Migrate to the new names; do not introduce the old ones.

## The Three Rules

```
1. update and view MUST be pure — no side effects, only return (Cmd, Model) / Html
2. Side effects go through Cmd-returning APIs — built-in packages first;
   any hand-written FFI package exposes ONLY Cmd-returning functions
3. Model holds data only — enums to eliminate impossible states;
   never Cmd, Msg, Request, or callbacks; collections immutable
```

**Impurity includes reads, not just writes.** Any `extern "js"` call that reads browser global state (`window.innerWidth`, `window.location.origin`, `Date.now()`, `localStorage.getItem`) inside update or view silently breaks idempotence. Values stable for the app's lifetime → read once in `main` before constructing the cell and store on `Model`; values that change over time → subscribe (`@sub.on_resize`, `@sub.every`, ...) and carry the payload through a `Msg`. See `references/ffi-packages.md` for both patterns with code.

## Use built-in effect packages before writing FFI

Rabbita ships Cmd/Sub-returning packages for most browser effects: `@http`, `@websocket`, `@clipboard`, `@nav`, `@dialog`, `@indexeddb`, `@url`, and `@sub` (resize, key, mouse, scroll, visibility, animation frame, timer, URL changes). Check these before hand-writing any `extern "js"`.

Avoid the escape hatches — `@cmd.custom_cmd`, `@sub.custom_sub`, `@cmd.effect`, `@cmd.attempt`, `@html.Attrs`, `@dom`, `trait Scheduler` — unless you are binding a JS library the built-ins genuinely don't cover (then follow `references/ffi-packages.md`).

Routing: map the URL into the model with `@html.a`, `@sub.on_url_changed`, and `@sub.on_url_request` — do not encode a navigation state machine in update.

## Route to references by task

Load the reference matching your current work BEFORE writing code:

| Task | Read |
|---|---|
| Using built-in effect packages, or binding a new JS library (dummy constructors, private externs, Cmd-returning API, wiring JS events back into the update loop via `Emit`, command constructor reference, package checklist) | `references/ffi-packages.md` |
| Designing or refactoring `Model` types (immutable collections, state enums, spotting hidden state machines, what must never live in a model) | `references/model-design.md` |
| Writing tests for update handlers (idempotence, dummy object trap, state transitions, test helpers) | `references/testing.md` |
| Writing or debugging views (positional vdom diffing & focus loss, view totality, per-dispatch cost, `@html` element surface, void elements, auto-scroll, embedding foreign DOM widgets) | `references/view-rendering.md` |

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

When a subsystem grows beyond ~5 messages or is likely to be reused, extract it into its own package with its own `Msg`.

Label every non-obvious `Msg` payload — `AgentProgress(run_id~ : Int, Event)`, not a bare positional `Int`. Name FFI/subsystem packages by domain (`alert`, `bridge`, `xterm`), never with an `_ffi` suffix.

## View & Rendering Rules (see `references/view-rendering.md`)

1. Rabbita diffs children **by index, not by key** — render conditional siblings AFTER stable stateful elements (inputs/textareas), or toggling them rebuilds those nodes and drops focus.
2. `view` must be **total**: one raise permanently kills the render loop. Guard any parser fed partial/streaming input.
3. Every dispatch re-runs the whole `view` — cache expensive derivations (parsed ASTs, layouts) in the Model at message time, never compute them in view.
4. Void elements (`hr`, `br`, `img`, `input`) take **zero** children (rabbita ≥0.12.4) — no trailing `@html.nothing`.
5. `on_click` exists only on some elements (`div`, `button` — not `a`/`span`); check the `.mbti`. Clickable text is a styled `button`. Since `on_click` takes an erased `Cmd`, subpackages accept `(payload) -> Cmd` callbacks instead of importing the root `Msg`.
6. `on_click` does **not** stop propagation — a clickable nested inside a clickable ancestor fires both handlers. Use the `@html.Attrs` event lambda with `event.stop_propagation()` (a legitimate escape-hatch use) or restructure to avoid nesting.
7. SSR/native builds: gate DOM-backed code behind `#cfg(target="js")` with inert native stubs; `@rabbita.delay` / `perform` / `attempt` are js-only — packages using them must declare js-only targets.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Hand-written FFI for http/websocket/clipboard/navigation/storage | Use the built-in package (`@http`, `@websocket`, ...) |
| `pub fn Terminal::write(...)` in FFI package | Make method `fn` (not `pub`); expose `pub fn write(...) -> Cmd` |
| `term.dispose()` in update | Return `@xterm.dispose(term)` as Cmd |
| `js_inner_width()` / `get_origin()` / `Date.now()` in update or view | Read once in `main`, store on Model; or subscribe and carry via Msg |
| Storing `Cmd`, `Msg`, `@http.Request`, or callbacks in Model (or globals) | Model holds plain data; construct commands fresh in update |
| Ignoring a returned `Cmd` / `Request` (`... \|> ignore`) | Return it from update (batch with `@rabbita.batch` if needed) |
| Business logic inside emit callbacks (`emit.map(s => Msg(s.has_prefix("x")))`) | Carry the raw payload in the Msg; decide in update |
| `Option` + `Bool` for lifecycle state | Replace with enum |
| Mutable `Array[T]` / `Map` mutated in place in model | Use `@immut/*` (e.g. `@vec.Vector[T]`); never mutate a model collection in place |
| FFI type without `dummy()` | Add `pub fn T::dummy() -> T` using `@js.Object::new().inner()` |
| New message handler without purity test | Add idempotence + dummy trap tests |
| `Dispatch` / `cell_with_dispatch` / `@cmd.raw_effect` in new code | `Emit` / `cell` (or `cell_with_emit`) / `@cmd.custom_cmd` |
| `@cmd.custom_cmd` inline in update | Use a built-in package, or move into an FFI package as a named Cmd function |
| Trailing `@html.nothing` on `hr`/`br`/`img`/`input` | Void elements take zero children (rabbita ≥0.12.4) |
| Parsing/deriving expensive data inside `view` | Cache it in the Model at message time; view reads the cache |
| Mutable `Ref` flag inside a sub loader / FFI closure to mute or filter events | Track connection identity (generation/id) in the Model and drop stale events in update — or fix the effect package itself |
| Fire-and-forget Cmd whose completion a later Msg depends on | Model the pending state as an enum and gate the dependent transition on the completion Msg |
| `moonbitlang/async/js_async.Promise::wait` inside a Cmd | Use `@rabbita/js` `Promise::wait` — Cmds run on Rabbita's own JS async runtime; mixing runtimes panics at resume |

## Red Flags in Code Review

- Hand-rolled `extern "js"` for something a built-in package covers
- FFI package exposes `pub fn` that returns `Unit` (should return `Cmd`)
- FFI type has no `dummy()` constructor
- `Cmd`, `Msg`, or `Request` values stored in a model field or global
- Mutable collection in a model field mutated in place
- `model.foo : T?` paired with `model.foo_loading : Bool` or `model.foo_visible : Bool`
- Any method call on a JS FFI object inside update
- New message handler without idempotence test
- Update branch that calls a function then returns `(@rabbita.none, model)`
- Conditional sibling rendered before a focus-holding element (index shift = focus loss)
- A raise-capable call inside `view` without a catch-and-fallback at the boundary
- Deprecated names (`Dispatch`, `cell_with_dispatch`, `raw_effect`) in new code
