---
name: rabbita
description: Use when writing or modifying update functions in Rabbita (Elm-architecture) MoonBit apps, creating FFI binding packages for Rabbita, designing Rabbita model types, or writing tests for Rabbita update handlers. Use when touching code that handles messages, modifies model, or interacts with JS FFI inside update.
---

# Rabbita

In Rabbita's Elm architecture, **`update` must be a pure function**: `(Emit[Msg], Msg, Model) -> (Cmd, Model)`. It returns a new model and commands describing side effects — it never executes side effects directly. This purity is enforced through effect-package design, model structure, and testing.

`Emit[Msg]` is a callable `(Msg) -> Cmd`: `emit(Inc)` yields a Cmd (usable directly as `on_click=emit(Inc)`), and `emit.map(payload => Msg(payload))` adapts it to `Emit[Payload]` for subsystem APIs. Keep emit lambdas short: `x => emit(UserMsg(x))`.

> Deprecated names you may see in old code: `Dispatch[Msg]` (now `Emit`), `cell_with_dispatch` (now `cell` / `cell_with_emit`), `@cmd.raw_effect` (now `@cmd.custom_cmd`). Migrate to the new names; do not introduce the old ones.

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
- Deprecated names (`Dispatch`, `cell_with_dispatch`, `raw_effect`) in new code
