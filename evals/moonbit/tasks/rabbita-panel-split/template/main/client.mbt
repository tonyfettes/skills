///|
/// A small ops console: a session log fills the page, and a bottom
/// "terminal" drawer accepts commands. Ctrl+` or the header button
/// toggles the drawer. Everything lives in this one package for now.
struct Model {
  entries : Array[String]
  panel_visible : Bool
  panel_input : String
} derive(Eq)

///|
enum Msg {
  TogglePanel
  PanelInputChanged(String)
  PanelSubmit
  ClearLog
  KeyPressed(@common.Keyboard)
}

///|
fn run_command(entries : Array[String], line : String) -> Array[String] {
  let echoed = entries + ["> " + line]
  match line {
    "help" => echoed + ["commands: help, status, clear"]
    "status" => echoed + ["session healthy, \{entries.length()} log lines"]
    "clear" => []
    _ => echoed + ["unknown command: \{line}"]
  }
}

///|
fn update(_ : @rabbita.Emit[Msg], msg : Msg, model : Model) -> (@rabbita.Cmd, Model) {
  match msg {
    TogglePanel =>
      (@rabbita.none, { ..model, panel_visible: !model.panel_visible })
    PanelInputChanged(text) => (@rabbita.none, { ..model, panel_input: text })
    PanelSubmit => {
      let line = model.panel_input.trim().to_owned()
      if line == "" {
        (@rabbita.none, model)
      } else {
        (
          @rabbita.none,
          { ..model, entries: run_command(model.entries, line), panel_input: "" },
        )
      }
    }
    ClearLog => (@rabbita.none, { ..model, entries: [] })
    KeyPressed(key) =>
      if key.code() == "Backquote" &&
        key.ctrl_key() &&
        !key.repeat() &&
        !key.is_composing() {
        (@rabbita.none, { ..model, panel_visible: !model.panel_visible })
      } else {
        (@rabbita.none, model)
      }
  }
}

///|
fn subscriptions(emit : @rabbita.Emit[Msg], _ : Model) -> @sub.Sub {
  @sub.on_key_down(key => emit(KeyPressed(key)))
}

///|
fn header_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="header") <| [
    @html.h1(class="title", "ops console"),
    @html.button(class="header-button", on_click=emit(ClearLog), "clear log"),
    @html.button(
      class="header-button",
      on_click=emit(TogglePanel),
      if model.panel_visible {
        "hide terminal"
      } else {
        "show terminal"
      },
    ),
  ]
}

///|
fn log_view(model : Model) -> @html.Html {
  @html.div(class="log") <| model.entries.map(entry => @html.p(
    class="log-line",
    entry,
  ))
}

///|
fn panel_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  // Conditional sibling rendered last so toggling it never shifts the
  // index of earlier nodes.
  if model.panel_visible {
    @html.div(class="terminal-panel") <| [
      @html.input(
        class="terminal-input",
        placeholder="type a command",
        value=model.panel_input,
        on_input=emit.map(text => PanelInputChanged(text)),
      ),
      @html.button(class="terminal-run", on_click=emit(PanelSubmit), "run"),
    ]
  } else {
    @html.nothing
  }
}

///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="page") <| [
    header_view(emit, model),
    log_view(model),
    panel_view(emit, model),
  ]
}

///|
fn main {
  fn app() {
    let (model, emit) = @rabbita.create_state(
      { entries: [], panel_visible: false, panel_input: "" },
      update=(model, msg, emit) => {
        let (cmd, model) = update(emit, msg, model)
        (model, cmd)
      },
      subscriptions=(model, emit) => subscriptions(emit, model),
    )
    model.map(model => view(emit, model))
  }

  @rabbita.new(app).mount("app")
}
