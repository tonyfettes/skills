# RUI — the Rabbita component library

`moonbit-community/rui` is a shadcn/ui "Nova"-styled component library for
Rabbita. It covers forms, dialogs, sheets, menus, popovers, tabs, collapsibles,
toasts, data tables, and Markdown (`moonbit-community/rui/markdown`). It needs no
Tailwind, CSS import, or build step: base styles are inline, and `@rui.theme`
emits the small sheet for hover, focus and motion.

Baseline: **rui 0.5.0** (2026-11-10). It is marked experimental, and APIs change
between minor versions. It pins `rabbita@0.17.0` (0.4.x pinned 0.16.4). In a
`moon.work` workspace only one Rabbita resolves, so bump rui and Rabbita together.

To check an API, open `pkg.generated.mbti` in the registry cache
(`$MOON_HOME/registry/cache/moonbit-community/rui/<ver>.zip`, which is
`~/Library/MoonBit/...` on macOS), or browse the showcase at
<https://moonbit-community.github.io/rabbita/components/>. Read the signature
before you guess a parameter.

Prefer rui over hand-rolled dialogs, menus, popovers, and focus or anchor
handling. Use your own markup only when no rui component fits.

## Read the return type: `Html` vs `Val[Html]`

rui has two kinds of API, and the signature tells you which one you have.

| Returns | Examples | Who owns the state |
| --- | --- | --- |
| `@html.Html` | `dialog`, `sheet`, `drawer`, `alert_dialog`, `button`, `*_header` / `*_footer`, and the `*_trigger` / `*_content` / `*_item` parts that take `open?` | Your model owns the state, or the browser does for a native `<dialog>`. These parts are pure view helpers. |
| `@rabbita.Val[@html.Html]` | `dropdown_menu`, `context_menu`, `popover`, `select`, `combobox`, `collapsible`, `command_dialog`, `sidebar_provider`, `date_picker` | A Rabbita component owns the state. |

The `Val` components follow the usual component rules (see "Components and
their inputs" in `view-rendering.md`):

- The body runs once at mount, and children captured there stay frozen.
- `default_open`, `default_value` and similar `default_*` arguments set only the
  initial state.
- Changes reach you only through `on_open_change`, `on_value_change` and the
  other `on_*_change` callbacks.
- To drive a `Val` component from the model, key it with `switch_by` so that it
  remounts when the model changes. The `by=` key must cover every input its body
  reads. If it does not, the component renders stale content.
- A few have `*_with_input` variants, such as `sidebar_provider_with_input`,
  that take a `Val[Input]`.

## Dialogs, sheets, drawers

`@rui.dialog` is a styled native `<dialog>` with no component state, and the
browser owns its visibility and focus.

- Open it from update with `@dialog.show(id)` (the `moonbit-community/rabbita/dialog`
  package). Close it with `@dialog.close(id)` or a `<form method="dialog">`
  submit button.
- `open=true` renders the dialog already open but non-modal. Use it only for
  the initial render, never to toggle the dialog from the model.
- Passing `on_cancel` blocks the default close on Escape. The handler must
  dispatch a `Msg` that closes the dialog, or it can never be dismissed.
- `closedby` sets how the dialog can be dismissed natively: `"any"` (outside
  click or Escape), `"closerequest"` (Escape only), or `"none"`.
- Give it a `dialog_title(id=...)` and link that id with
  `attrs=@html.Attrs::build().aria_labelledby(...)`.

## Menus: one controlled instance per surface

Never wrap each list row, or other dynamic content, in its own
`@rui.context_menu` / `dropdown_menu`. A per-row instance freezes that row's
content at mount. The usual workaround is a hand-written
`switch_by(by=revision)` cache, and it goes stale as soon as `revision` misses
one input. One real case: `aria-current` stayed stale because the key omitted
the active flag.

Use a single menu for the whole surface instead:

1. Keep the open state in the model, for example
   `open_menu : (target_key, anchor)?`. The anchor is a pointer `(x, y)` or a
   trigger element.
2. Rows only emit a stable target key, such as `OpenMenu(id, Pointer(x, y))`.
   Nothing about the menu is rendered inside a row.
3. At surface level, render one `@rui.dropdown_menu(id=..., default_open=true,
   on_open_change=...)` under `switch_by`, keyed by the open target.
   - For a pointer menu, put a zero-size
     `@rui.popover_anchor(style=["position:fixed;left:\{x}px;top:\{y}px;width:0;height:0"])`
     inside it.
   - Resolve the entries from the current model.
4. When `on_open_change(false)` fires, dispatch a `Msg` that clears `open_menu`.

Do not ask for "reactive children" on rui triggers. If a view needs them, the
state is in the wrong place.

rui menus and popovers are native `popover="auto"` elements, which live in the
top layer, and rui calls `show_popover` itself. That suits menus opened by a
click or right-click. A menu whose visibility follows typing, such as composer
autocomplete or slash commands, should not be a rui menu: use `position: fixed`
plus anchor positioning in the app's own markup (View rule 9 in `SKILL.md`).

`@rui.popover_open(id)` / `popover_close(id)` / `popover_toggle(id)` are `Cmd`s
for driving a popover from update.

## Theme and customization

- Wrap the rui subtree, normally the app root, in `@rui.theme(...)`. Without the
  wrapper, components render but lose hover, focus-visible, and motion styles.
  `theme(style=["display:contents"], ...)` adds no layout box.
- `@rui.theme` sets `--rui-*` tokens inline on its wrapper. To map them onto the
  app's design tokens, append CSS variables through `theme(style=[...])`. A
  stylesheet rule on the same element needs `!important` to win over the
  inline values.
- For each component, use the `class`, `style` and `attrs` parameters.
- If you need a different DOM structure, state model, or interaction policy,
  copy that component's `.mbt` source into the app, as upstream recommends. Do
  not write CSS selectors against rui's internal markup.
