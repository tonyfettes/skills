# View and Rendering Rules

How Rabbita (0.16.x–0.17.0) actually renders — positional vs keyed child diffing, what reruns on a change, view totality. All rules below come from real production bugs.

## The diffing model: `Array` children by index, `Map` children by key

A child list is diffed according to the form it was passed in (`internal/vdom/diff.mbt`, `diff_children`):

- **`Array[Html]` (and `Vector`/`List`) children are matched positionally.** If a conditional sibling appears/disappears, every later sibling shifts index and gets **morphed into the node that used to be at that index** — a `<textarea>` shifted from index 0 to 1 is rebuilt from scratch, losing focus, selection, and scroll state.
- **`Map[String, Html]` children are keyed.** Keys missing from the new map are removed, keys present in both are diffed in place and relocated to the new order, new keys are inserted. Order follows map insertion order; keys must be unique and stable (business ids, not positions). Changing a key removes the old node and creates a new one.
- Switching a slot between the two forms (or to raw HTML) clears and rebuilds that parent's children.

Rules:

- **Render conditional siblings AFTER stable stateful elements** (inputs, textareas, anything holding focus/DOM state) when the list is an array. A completion menu toggled above the composer's textarea steals focus mid-keystroke; appended last, it never shifts the textarea's index.
- **Dynamic lists (insert/remove/reorder) are keyed maps**, built with a `Map[String, Html]` literal or a `for` loop over the model collection. Items that own local state additionally go through `Val::assoc_by(component, by=item => item.id)` so each key keeps its own incremental branch.
- If neither ordering nor keying fits, keep sibling indices stable another way: keep the conditional element always present and toggle CSS visibility, or restructure the tree. Do NOT rely on an `@html.nothing` placeholder to hold the slot in a void element (they take no children at all — see below).
- Keys given to `assoc`/`assoc_by` identify incremental branches only; they are not attached to the resulting `Html`. Key the `Map` you pass to the element as well when the DOM order matters.

## `view` must be total — one raise stops rendering

If a render callback throws, Rabbita's render loop stops: the UI freezes on the last successfully rendered frame while the app keeps running underneath. Worse, if the poison input lives in the model, **every** subsequent re-render throws again.

- `view` must never raise. Guard any parser fed partial/streaming input (markdown renderers on truncated text are the canonical crash) — catch at the boundary and render a fallback.
- This is the same purity rule as update, applied to failure: views are pure AND total.

## What reruns on a change

The incremental graph reruns a `map`/`view` callback only when one of its `Val` inputs produced a value that is not `Eq` to the previous one; equal results stop propagation. But **a render callback rebuilds all of the `Html` it returns** — so a single `model.view(m => whole_page(m))` still re-renders the whole page on every model change, and expensive derivations inside it multiply by message rate (re-parsing an accumulated markdown transcript on every streaming delta is quadratic and was both a perf sink and the crash amplifier above).

- **Derive narrower `Val`s**: `model.map(m => m.status).view(...)` reruns only when `status` changes. Split large views into child components; combine with `view2`..`view9`. For a page/route enum, `page.switch(p => match p { ... })` (tag from `@rabbita.Enumerate`, or `switch_by(by=...)`) keeps one component per tag: it is built from the tag's first value and disposed when the tag changes, so payload changes under the same tag must reach it through its own `Val` inputs.
- **Cache expensive derived data (parsed ASTs, layouts) in the Model at message time**, in update, not in view. View reads the cached value.
- **`@html.memo(inputs, render)`** (0.15.7+) skips an unchanged subtree inside a render callback; `inputs : Hash` must cover every value the subtree reads. There is no `@html.lazy`. `@html.memo_by(value, render, by~ : (T) -> Int)` takes the cache key directly — the key is the *whole* cache key (no value equality, closure changes go unseen). For `assoc_by` rows, allocate a `Ref[Int]` counter inside the branch closure, bump it where the row's `Val` recomputes, and use it as the key: a per-branch counter cannot collide across rows. A memo node against a non-memo node at the same position is remove + insert, so wrap consistently.
- `Eq` must see every change: mutate nothing in place inside the model; use `@vector.Vector` and friends.

## Components and their inputs

A component is a function that runs **once**, at mount, and returns a
`Val[Html]`. Two consequences decide where state can live:

1. **Plain parameters are frozen.** Anything the parent may later change must
   be a `Val[T]` (or arrive as a `Msg`). A component that takes
   `label : String` shows the first label forever.
2. **An input change is not an event.** `create_state_with_input` lets
   `update` and `view` *read* the latest input, but changing the input alone
   sends no message, runs no `update`, and re-evaluates no subscription
   (subscriptions are recomputed at init and after each `Msg`). The view layer
   propagates automatically (`state.view2(input, ...)`); the effect layer is
   driven by `Msg` alone.

So a component may own its state when all its effects are `Msg`-driven. When
an effect must fire on a transition the component cannot observe — "this page
was opened", "focus moved here" — pick one:

| Route | Cost |
|---|---|
| Keep the state in the parent model (as an abstract type) and forward one `Msg` variant | None; this is the default |
| Mount per occurrence with `Val::switch_by` and start the effect in `init` | Re-runs on every open; **in-flight work dies with the subtree** — only for dispose-on-close widgets |
| Fetch in `init` of an always-mounted component | Fires at app start even if never shown; "reopen = retry" is lost |
| Poll the input from a `@sub.every` timer | A permanent timer for a one-shot need |

Never signal such a change through a rendered `data-*` attribute and a
`MutationObserver`.

**Do not wrap dynamic content in a per-item stateful component.** A wrapper
component (a context menu or dropdown around each list row) freezes the
children it was built with. The usual patch — a `switch_by(by=revision)` cache
that rebuilds the wrapper when the row changes — goes stale on whichever field
the revision forgot (seen: `aria-current` stuck after the active row changed).
Keep one controlled instance for the whole list, with the open target and its
anchor in that instance's state; rows only dispatch a stable target key, and
the entries are resolved from the latest input on every render.

## Component identity is DOM identity only when keyed

Switching a positional child from one component to another of the same tag
(`[topbar, conversation, composer]`, new conversation → new component) does
**not** create a new element: the diff patches the existing `<section>` in
place. Code in the new component that grabbed the element early is now holding
the previous component's nodes, and an identity check afterwards says "same".

- Key the container (`Map[String, Html]`, key includes what identifies the
  component) so a new component gets a new element.
- Never resolve DOM in a subscription loader — it runs during the graph read,
  before the DOM update. Schedule the lookup as an after-render command.
- An imperative island may hold on to an element only if that element's
  children are not in the VDOM; everything else is re-resolved after each
  render.

## Event handlers: emit first, decide in update

A handler closure is built at render time and captures the values of that
frame. If it branches on one of them before emitting, events that arrive
before the next paint are judged against stale state:

```moonbit
// BAD — `valid` is from the last painted frame; type-then-Enter in one frame is dropped
on_keydown=Emit(key => if key.key() == "Enter" && valid { emit(Create) } else { @rabbita.none })

// GOOD — carry the raw key; update checks the current model
on_keydown=emit.map(key => KeyDown(key))
```

Related: the diff patches an input's `value` by comparing the new vnode with
the last painted one, never with the live DOM, and paints coalesce per
animation frame. A burst typed faster than the frame rate, followed by a state
rewrite that lands back on the last painted value, leaves the DOM showing the
raw typed text while the model is correct. In browser tests, type with a
per-key delay so each keystroke gets a paint.

## Menus and popovers that follow the model

The browser top layer (`popover`, `<dialog>.showModal()`) paints above every
ordinary overlay, and Rabbita has no node-inserted hook: any path that
re-creates the anchor's DOM leaves an open top-layer popover hidden, and every
modal, drawer or backdrop that should cover it needs its own dismissal rule.

- A menu whose visibility is derived from model or input state (completion
  menus, status details) uses `position: fixed` + CSS anchor positioning
  inside a `container-type: size` ancestor. That ancestor is the containing
  block and stacking context: an overflow container cannot clip the menu, and
  overlays still cover it.
- Use the top layer only for click-opened menus whose toggle command itself
  calls `show()`.

## The `@html` element surface — check the `.mbti`, don't guess

- **Void elements (`hr`, `br`, `img`, `input`) take ZERO positional children.** Passing a trailing `@html.nothing` (pre-0.12.4 style) is a compile error. When bumping rabbita or rebasing old branches, sweep for trailing `nothing` on void elements.
- **`on_click` exists only on `div`, `button`, `li`, `ul`** (NOT `a` or `span`; `on_mousedown`/`on_mouseup` only on `div`/`canvas`). Clickable inline text is a CSS-styled `button`. Verify against `pkg.generated.mbti` before claiming an attribute exists.
- `on_click` takes a type-erased `@cmd.Cmd`. Useful consequence: a subpackage can accept `on_open : (String) -> @cmd.Cmd` callbacks and never import the root `Msg` — this is the standard way to avoid circular deps between view subpackages and the app root.
- **`on_click` does not stop propagation.** A button inside a clickable row dispatches BOTH handlers on one click. When nesting is unavoidable, drop to the `@html.Attrs` event lambda: `attrs=@html.Attrs::build().on_click(event => { event.stop_propagation(); emit(Msg) })` — one of the few legitimate `@html.Attrs` uses.
- **File inputs fire a plain `Event` on change, not `InputEvent`** — `@html.Attrs::on_change` does a `to_input_event().unwrap()` internally (`html/attrs_event.mbt`) and panics on `<input type=file>` (symptom: clicking the file picker "does nothing"). Use the element helper's `on_change` purely as a trigger and read the file inside an FFI Cmd. `@dom` has no `File`/`FileList` binding: a `File` is a `Blob`, so the extern (new inline JS — needs approval) returns `input.files[0]` as `@dom.Blob`, and the async `Blob::text()` / `bytes()` run inside `@cmd.attempt`.
- **Boolean props are DOM properties.** `disabled~`, `read_only~`, `checked~` etc. are assigned as `element[key]`, and a prop omitted on re-render is reset to `""`/`null`. A raw `Attrs::property(key, ...)` needs the camelCase DOM name (`readOnly`).
- **`@html.svg` / `@html.math` create HTML-namespace elements** (still true on 0.17.0) — the SVG never renders. Build SVG with the `@svg` package (`@svg.svg(view_box=..., [...])` returns `Html` with the SVG namespace).

## Auto-scroll: gate on a pinned flag, subscribe in capture phase

Unconditionally forcing `scrollTop` to bottom on every streaming delta makes it impossible to scroll up while output is generating. The working pattern:

- `pinned : Bool` on the Model; the scroll-to-bottom Cmd (`@nav.scroll_to_bottom` or a named FFI Cmd) fires only when pinned.
- Track user scrolling with a **document-level capture-phase** scroll listener (scroll events don't bubble, and a capture listener survives the container being re-rendered); dispatch `Pinned(Bool)` only when the state actually changes.
- Explicit user actions (send message, jump-to-bottom button) force re-pin.

## Embedding a foreign imperative DOM widget

Rabbita has no built-in escape hatch for third-party DOM widgets (editors, terminals). The pattern that works:

1. Give the widget a **stable, childless container node** whose identity never changes: a keyed entry in a `Map[String, Html]` child list, or an array slot before any conditional sibling. The diff leaves a stable childless node untouched.
2. Mount imperatively via a named Cmd from an FFI package (`kind=AfterRender`), never inline in update. **Bundle open → fit → initial writes into that ONE AfterRender Cmd** — splitting them across Cmds produces ordering bugs (fit before mount, writes before open).
3. **Spike survive-re-render behavior first** — mount the widget, force unrelated model changes, confirm the widget's DOM is untouched — before building the feature on top. Skipping the spike produced enough regressions that a whole feature had to be reverted.
4. **Widget APIs are often asynchronous** — xterm's `term.write()` drains on a later event-loop turn. Anything that must observe the written state (serialize/snapshot, compact a delta log, dispose, remount) must sequence through the completion callback (`term.write(data, cb)`). Never mount a replacement widget into the same container before the old instance is disposed — it reads the stale DOM nodes and comes up blank/mis-sized.
5. **Prefer a subscription-owned lifecycle** for DOM-bound widgets: dispose in the subscription's unload (like `@websocket.listen`), rather than exposing a user-callable `close`/`dispose` Cmd. Keyed global registries are justified only for non-DOM background resources (websocket-style string ids).
6. **Pick one scroll owner.** xterm has its own scrollback viewport that eats wheel events — set `scrollback=0` when the page should scroll, or vice versa; don't leave both scrolling.
7. **Terminal input is not just keystrokes**: xterm `onData` also carries the terminal's automatic replies to escape-sequence queries (DA/DSR/CPR) — gate the `onData → server` path during history replay or the replies get fed back as typed input. Use `attachCustomKeyEventHandler` for modifier shortcuts (runs before the hidden textarea, no manual modifier tracking); IME composition arrives as keyDown `keyCode 229` + composition events — don't double-send.
8. **Never iterate a live DOM collection while removing its members.** `@dom.Element::get_children()` returns the live `HTMLCollection`, and its `iter()` reads `item(index)` lazily — removing during the walk shrinks the collection under the cursor, so every other child survives and later re-renders inherit the half-cleared DOM. Snapshot first: `for child in parent.get_children().iter().to_array() { ... }` — see "snapshot live DOM collections" in `ffi-packages.md`.
9. **Don't rely on xterm's hidden textarea for IME input** — browsers disagree on whether IME punctuation arrives as committed text or raw keydowns (Chrome delivers CJK `？` as a plain `Shift+/` keydown). Give IME users a visible composer textarea and forward committed text. Debug input bugs with a code-point event trace (keydown / beforeinput / input / composition / onData), not by guessing.

## Mobile keyboards & focus

Soft keyboards appear and disappear with focus — the model must drive focus explicitly:

- `autofocus=true` sets the DOM `autofocus` property and leaves the rest to the browser, which **skips autofocus whenever the document already has a focused element**. It works for an element mounted while nothing holds focus (first paint, or after a tap on a control that does not take focus, as on iOS Safari). It does nothing for an input inserted in response to a click on a focusable control in Chromium — the button just clicked still has focus — and it never fires again for an element that is reused rather than remounted.
- So when an update branch inserts or re-enables an input the user should type into, return an explicit focus Cmd keyed by element id: a named Cmd function with `kind=AfterRender` built on the typed `@dom` calls (`Document::get_element_by_id`, `focus()`), not an inline DOM poke and not a new `extern "js"`. Keep one shared focus helper per app rather than a copy per package. Decide which element should end up focused from the *next* state, not the current one. Keeping `autofocus=true` as well is harmless.
- The same Cmd covers refocusing an element that already exists — a composer whose view/task switches under it (an "open" composer without focus means no keyboard), or an input that was `disabled` during a request (disabling drops focus).
- Blur (and thus dismiss the keyboard) before opening overlays/drawers; keep one element focused across soft-key taps so the keyboard doesn't flicker closed.
- iOS Safari auto-zooms any focused text control whose computed font-size is < 16px — fix with real 16px type (optionally `scale()` compensation), never with `user-scalable=no`.
