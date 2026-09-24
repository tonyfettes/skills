# Model Design

## Rule: The model implements `Eq`, and `Eq` must see every change

`create_state`, `create_pure_state`, `create_variable`, and every `Val::map`
input are bounded by `Eq` (0.16). The runtime compares the new model with the
old one and stops propagation when they are equal, so:

- `derive(Eq)` on the model and every type nested in it.
- Never mutate a model value in place — an in-place change leaves the old
  snapshot equal to the new one and the view never reruns.
- A field holding a JS handle (`@js.Value` has no `Eq`) needs a hand-written
  `impl Eq` for the wrapper: compare by a generation/id you assign when the
  handle is created, or wrap the handle in a state enum whose payload is
  compared by identity. Do not derive `Eq` on a struct that only exists to
  make tests compile.

## Rule: The model holds plain data only

Never store these in a model field (or a global):

- `Cmd` — commands are constructed fresh in update and returned
- `Msg` or message-producing callbacks/`Emit` values
- `@http.Request` / `RequestWithBody`
- FFI handles you don't have to hold: built-in effects are keyed, not handle-based — e.g. `@websocket` addresses connections by **string id** (`@websocket.send("chat-client", ...)`), so the model only needs a plain status enum, not a socket object. Only genuinely hand-bound JS objects (e.g. an xterm `Terminal`) belong in the model, wrapped in a state enum.

Routing state is also not yours to encode by hand: map the URL into the model via `@sub.on_url_changed` / `@sub.on_url_request` and `@html.a`, rather than building a navigation state machine in update.

## Rule: Collections in the model MUST be immutable

Use `@vector.Vector[T]` (from `moonbitlang/core/immut/vector`), never `Array[T]`. `Array[T]` is mutable — a handler could accidentally mutate it, breaking idempotence, letting stale references in prior model snapshots change underfoot, and hiding the change from `Eq` so the view never reruns. `Vector` is also what `Val::assoc` / `assoc_by` take for keyed child components.

```moonbit
// moon.pkg
import {
  "moonbitlang/core/immut/vector",
}
```

```moonbit
// BAD — mutable, update could push/clear in place
struct Model {
  servers : Array[ServerEntry]
  threads : Array[Thread]
} derive(Eq)

// GOOD — immutable persistent vector
struct Model {
  servers : @vector.Vector[ServerEntry]
  threads : @vector.Vector[Thread]
} derive(Eq)
```

Use `@vector.Vector::push`, `set`, `filter`, `map`, etc. — they return a new Vector. The old model snapshot is never mutated.

The same rule applies to maps and sets: prefer `@immut/hashmap`, `@immut/sorted_map`, `@immut/sorted_set` over their mutable counterparts. (Upstream examples sometimes keep `Array[T]` but copy on every change — `xs.copy()` then push/insert; that discipline is acceptable, but a persistent structure makes the invariant unforgeable.)

## Rule: Use enums to make invalid states unrepresentable

Multiple related fields (especially `Option` + `Bool` combinations) encode a state machine. Replace them with an enum.

### BAD — boolean flags create impossible states

```moonbit
struct Model {
  terminal : @xterm.Terminal?   // None or Some
  terminal_mounting : Bool      // is mount in progress?
  terminal_visible : Bool       // is panel shown?
}
```

This allows 2 x 2 x 2 = 8 combinations, but only 4 are valid. The invalid ones cause bugs:
- `terminal: None, terminal_mounting: false, terminal_visible: true` — visible but nothing to show
- `terminal: Some(_), terminal_mounting: true, terminal_visible: false` — mounted but still mounting?

### GOOD — enum encodes exactly the valid states

```moonbit
pub(all) enum TermState {
  Closed                    // no terminal
  Mounting                  // mount in progress, waiting for Mounted msg
  Open(@xterm.Terminal)     // mounted and visible
  Hidden(@xterm.Terminal)   // mounted but panel collapsed
}

struct Model {
  term_state : TermState
}
```

4 states, all valid. Pattern matching is exhaustive — the compiler forces you to handle every case.

## How to identify hidden state machines

Look for these patterns in your model:

| Smell | Likely state machine |
|-------|---------------------|
| `foo : T?` + `foo_visible : Bool` | Lifecycle enum (Closed/Open/Hidden) |
| `foo : T?` + `foo_loading : Bool` | Loading enum (Idle/Loading/Ready(T)/Error) |
| `connected : Bool` + `retrying : Bool` + `attempts : Int` | Connection enum (Disconnected/Connecting/Connected/Reconnecting) |
| Two booleans that are never both true | Two-variant enum |

## Helper methods on state enums

Add methods to avoid match boilerplate in the view:

```moonbit
fn TermState::is_visible(self : TermState) -> Bool {
  match self {
    Open(_) | Mounting => true
    _ => false
  }
}
```

## Transitions become exhaustive matches in update

```moonbit
ToggleTerminal => {
  match model.term_state {
    Closed => ({ ..model, term_state: Mounting }, mount_cmd)
    Mounting => (model, @rabbita.none)  // already in progress
    Open(term) => ({ ..model, term_state: Hidden(term) }, @rabbita.none)
    Hidden(term) => ({ ..model, term_state: Open(term) }, fit_cmd)
  }
}
```

No `if visible && terminal.is_some() && !mounting` — the enum handles it.
