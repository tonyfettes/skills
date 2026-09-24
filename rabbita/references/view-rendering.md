# View and Rendering Rules

How Rabbita (0.16.x) actually renders — positional vs keyed child diffing, what reruns on a change, view totality. All rules below come from real production bugs.

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

- **Derive narrower `Val`s**: `model.map(m => m.status).view(...)` reruns only when `status` changes. Split large views into child components; combine with `view2`..`view9`.
- **Cache expensive derived data (parsed ASTs, layouts) in the Model at message time**, in update, not in view. View reads the cached value.
- **`@html.memo(inputs, render)`** (0.15.7+) skips an unchanged subtree inside a render callback; `inputs : Hash` must cover every value the subtree reads. There is no `@html.lazy`. Wrap `assoc_by` rows with a per-branch key rather than a global counter (see memory `rabbita-lazy-thunk-missing`).
- `Eq` must see every change: mutate nothing in place inside the model; use `@vector.Vector` and friends.

## The `@html` element surface — check the `.mbti`, don't guess

- **Void elements (`hr`, `br`, `img`, `input`) take ZERO positional children.** Passing a trailing `@html.nothing` (pre-0.12.4 style) is a compile error. When bumping rabbita or rebasing old branches, sweep for trailing `nothing` on void elements.
- **`on_click` exists only on some elements** (`div`, `button`, `li`, `ul`, ... — NOT `a` or `span`). Clickable inline text is a CSS-styled `button`. Verify against `pkg.generated.mbti` before claiming an attribute exists.
- `on_click` takes a type-erased `@cmd.Cmd`. Useful consequence: a subpackage can accept `on_open : (String) -> @cmd.Cmd` callbacks and never import the root `Msg` — this is the standard way to avoid circular deps between view subpackages and the app root.
- **`on_click` does not stop propagation.** A button inside a clickable row dispatches BOTH handlers on one click. When nesting is unavoidable, drop to the `@html.Attrs` event lambda: `attrs=@html.Attrs::build().on_click(event => { event.stop_propagation(); emit(Msg) })` — one of the few legitimate `@html.Attrs` uses.
- **File inputs fire a plain `Event` on change, not `InputEvent`** — `@html.Attrs::on_change` does a `to_input_event().unwrap()` internally (`html/attrs_event.mbt`) and panics on `<input type=file>` (symptom: clicking the file picker "does nothing"). Use the element helper's `on_change` purely as a trigger and read the file through a DOM reference inside an FFI Cmd (`@dom.File::text()`).
- **`disabled~` on `button` is a DOM property.** Toggling it true→false on the same button is fine, but when a positional slot morphs from a disabled button into a different button the property is not removed (see memory `rabbita-disabled-property-sticks`). Key the children or use `Attrs::build().disabled(...)`, which writes an attribute.

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

- For focus-on-mount of a conditionally rendered element, use the built-in `autofocus=true` attribute (`@html.input` / `textarea` / `button` all take it) — the node is fresh on each mount, so the attribute fires every time. Do NOT reach for a `@cmd.custom_cmd` + `@dom` lookup to focus it; that's the escape hatch (and needs user approval like any new inline JS). If the element is reused rather than remounted (keyed or stable slot), `autofocus` does not fire again — issue the focus Cmd below.
- Issue an explicit focus Cmd (a named Cmd from an FFI package, `kind=AfterRender`, not an inline DOM poke) only when refocusing an element that already exists — e.g. a composer whose view/task switches under it; an "open" composer without focus means no keyboard.
- Blur (and thus dismiss the keyboard) before opening overlays/drawers; keep one element focused across soft-key taps so the keyboard doesn't flicker closed.
- iOS Safari auto-zooms any focused text control whose computed font-size is < 16px — fix with real 16px type (optionally `scale()` compensation), never with `user-scalable=no`.
