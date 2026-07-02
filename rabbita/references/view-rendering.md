# View and Rendering Rules

How Rabbita actually renders — positional vdom diffing, view totality, and per-dispatch cost. All rules below come from real production bugs.

## The diffing model: children are matched by index, not by key

Rabbita has no keyed diff. Children of a node are diffed positionally: if a conditional sibling appears/disappears, every later sibling shifts index and gets **morphed into the node that used to be at that index** — a `<textarea>` shifted from index 0 to 1 is rebuilt from scratch, losing focus, selection, and scroll state.

Rules:

- **Render conditional siblings AFTER stable stateful elements** (inputs, textareas, anything holding focus/DOM state). A completion menu toggled above the composer's textarea steals focus mid-keystroke; appended last, it never shifts the textarea's index.
- If ordering can't put the stateful element first visually, keep the slot stable — render `@html.nothing`-style placeholders is NOT an option for void slots (see below); instead keep the element always present and toggle CSS visibility, or restructure the tree.

## `view` must be total — one raise kills the render loop permanently

If `view` throws, Rabbita's render loop dies for good: the UI freezes on the last successfully rendered frame while the app keeps running underneath. Worse, if the poison input lives in the model, **every** subsequent re-render throws again.

- `view` must never raise. Guard any parser fed partial/streaming input (markdown renderers on truncated text are the canonical crash) — catch at the boundary and render a fallback.
- This is the same purity rule as update, applied to failure: views are pure AND total.

## Every dispatch re-runs the whole `view`

There is no incremental recompute: each `Msg` runs `view(emit, model)` in full. Expensive derivations inside view multiply by message rate — re-parsing an accumulated markdown transcript on every streaming delta is quadratic and was both a perf sink and the crash amplifier above.

- **Cache expensive derived data (parsed ASTs, layouts) in the Model at message time**, in update, not in view. View reads the cached value.

## The `@html` element surface — check the `.mbti`, don't guess

- **Void elements (`hr`, `br`, `img`, `input`) take ZERO positional children** (since rabbita 0.12.4). Passing a trailing `@html.nothing` (old 0.12.1 style) is a compile error. When bumping rabbita or rebasing old branches, sweep for trailing `nothing` on void elements.
- **`on_click` exists only on some elements** (`div`, `button`, ... — NOT `a` or `span`). Clickable inline text is a CSS-styled `button`. Verify against `pkg.generated.mbti` before claiming an attribute exists.
- `on_click` takes a type-erased `@cmd.Cmd`. Useful consequence: a subpackage can accept `on_open : (String) -> @cmd.Cmd` callbacks and never import the root `Msg` — this is the standard way to avoid circular deps between view subpackages and the app root.
- **`on_click` does not stop propagation.** A button inside a clickable row dispatches BOTH handlers on one click. When nesting is unavoidable, drop to the `@html.Attrs` event lambda: `attrs=@html.Attrs::build().on_click(event => { event.stop_propagation(); emit(Msg) })` — one of the few legitimate `@html.Attrs` uses.
- **File inputs fire a plain `Event` on change, not `InputEvent`** — `@html.Attrs::on_change` does a `to_input_event().unwrap()` internally and panics on `<input type=file>` (symptom: clicking the file picker "does nothing"). Use the element helper's `on_change` purely as a trigger and read the file through a DOM reference inside an FFI Cmd (`@dom.File::text()`).

## Auto-scroll: gate on a pinned flag, subscribe in capture phase

Unconditionally forcing `scrollTop` to bottom on every streaming delta makes it impossible to scroll up while output is generating. The working pattern:

- `pinned : Bool` on the Model; the scroll-to-bottom Cmd fires only when pinned.
- Track user scrolling with a **document-level capture-phase** scroll listener (scroll events don't bubble, and a capture listener survives the container being re-rendered); dispatch `Pinned(Bool)` only when the state actually changes.
- Explicit user actions (send message, jump-to-bottom button) force re-pin.

## Embedding a foreign imperative DOM widget

Rabbita has no keyed diff and no built-in escape hatch for third-party DOM widgets (editors, terminals). The pattern that works:

1. Give the widget a **stable, childless container node** placed where sibling indices never shift (see the diffing rule above) — positional diffing leaves a stable childless node untouched.
2. Mount imperatively via a named Cmd from an FFI package (`kind=AfterRender`), never inline in update. **Bundle open → fit → initial writes into that ONE AfterRender Cmd** — splitting them across Cmds produces ordering bugs (fit before mount, writes before open).
3. **Spike survive-re-render behavior first** — mount the widget, force unrelated model changes, confirm the widget's DOM is untouched — before building the feature on top. Skipping the spike produced enough regressions that a whole feature had to be reverted.
4. **Widget APIs are often asynchronous** — xterm's `term.write()` drains on a later event-loop turn. Anything that must observe the written state (serialize/snapshot, compact a delta log, dispose, remount) must sequence through the completion callback (`term.write(data, cb)`). Never mount a replacement widget into the same container before the old instance is disposed — it reads the stale DOM nodes and comes up blank/mis-sized.
5. **Prefer a subscription-owned lifecycle** for DOM-bound widgets: dispose in the subscription's unload (like `@websocket.listen`), rather than exposing a user-callable `close`/`dispose` Cmd. Keyed global registries are justified only for non-DOM background resources (websocket-style string ids).
6. **Pick one scroll owner.** xterm has its own scrollback viewport that eats wheel events — set `scrollback=0` when the page should scroll, or vice versa; don't leave both scrolling.
7. **Terminal input is not just keystrokes**: xterm `onData` also carries the terminal's automatic replies to escape-sequence queries (DA/DSR/CPR) — gate the `onData → server` path during history replay or the replies get fed back as typed input. Use `attachCustomKeyEventHandler` for modifier shortcuts (runs before the hidden textarea, no manual modifier tracking); IME composition arrives as keyDown `keyCode 229` + composition events — don't double-send.
8. **Don't rely on xterm's hidden textarea for IME input** — browsers disagree on whether IME punctuation arrives as committed text or raw keydowns (Chrome delivers CJK `？` as a plain `Shift+/` keydown). Give IME users a visible composer textarea and forward committed text. Debug input bugs with a code-point event trace (keydown / beforeinput / input / composition / onData), not by guessing.

## Mobile keyboards & focus

Soft keyboards appear and disappear with focus — the model must drive focus explicitly:

- Issue an explicit focus Cmd whenever a composer is shown or the active view/task switches; an "open" composer without focus means no keyboard.
- Blur (and thus dismiss the keyboard) before opening overlays/drawers; keep one element focused across soft-key taps so the keyboard doesn't flicker closed.
- iOS Safari auto-zooms any focused text control whose computed font-size is < 16px — fix with real 16px type (optionally `scale()` compensation), never with `user-scalable=no`.
