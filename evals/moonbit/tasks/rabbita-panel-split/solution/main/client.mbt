///|
/// Root package: owns the session log; the terminal drawer lives in the
/// `terminal` package and is wired in by message.
struct Model {
  entries : Array[String]
  terminal : @terminal.Model
} derive(Eq)

///|
enum Msg {
  Terminal(@terminal.Msg)
  ClearLog
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
    Terminal(msg) => {
      let (terminal, submitted) = @terminal.update(msg, model.terminal)
      let entries = match submitted {
        Some(line) => run_command(model.entries, line)
        None => model.entries
      }
      (@rabbita.none, { terminal, entries })
    }
    ClearLog => (@rabbita.none, { ..model, entries: [] })
  }
}

///|
fn subscriptions(emit : @rabbita.Emit[Msg], _ : Model) -> @sub.Sub {
  @terminal.subscriptions(emit.map(msg => Terminal(msg)))
}

///|
fn header_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="header") <| [
    @html.h1(class="title", "ops console"),
    @html.button(class="header-button", on_click=emit(ClearLog), "clear log"),
    @html.button(
      class="header-button",
      on_click=emit(Terminal(@terminal.Toggle)),
      if model.terminal.visible {
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
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  @html.div(class="page") <| [
    header_view(emit, model),
    log_view(model),
    @terminal.view(emit.map(msg => Terminal(msg)), model.terminal),
  ]
}

///|
fn main {
  fn app() {
    let (model, emit) = @rabbita.create_state(
      { entries: [], terminal: @terminal.Model::initial() },
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
