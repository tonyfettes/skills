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

## Auto-scroll: gate on a pinned flag, subscribe in capture phase

Unconditionally forcing `scrollTop` to bottom on every streaming delta makes it impossible to scroll up while output is generating. The working pattern:

- `pinned : Bool` on the Model; the scroll-to-bottom Cmd fires only when pinned.
- Track user scrolling with a **document-level capture-phase** scroll listener (scroll events don't bubble, and a capture listener survives the container being re-rendered); dispatch `Pinned(Bool)` only when the state actually changes.
- Explicit user actions (send message, jump-to-bottom button) force re-pin.

## Embedding a foreign imperative DOM widget

Rabbita has no keyed diff and no built-in escape hatch for third-party DOM widgets (editors, terminals). The pattern that works:

1. Give the widget a **stable, childless container node** placed where sibling indices never shift (see the diffing rule above) — positional diffing leaves a stable childless node untouched.
2. Mount imperatively via a named Cmd from an FFI package (`kind=AfterRender`), never inline in update.
3. **Spike survive-re-render behavior first** — mount the widget, force unrelated model changes, confirm the widget's DOM is untouched — before building the feature on top. Skipping the spike produced enough regressions that a whole feature had to be reverted.
