///|
/// The terminal drawer owns its visibility, its input buffer, and the
/// Ctrl+` shortcut. The root package wires it in with `emit.map`.
pub struct Model {
  visible : Bool
  input : String
} derive(Eq)

///|
pub fn Model::initial() -> Model {
  { visible: false, input: "" }
}

///|
pub(all) enum Msg {
  Toggle
  InputChanged(String)
  Submit
  KeyPressed(@common.Keyboard)
}

///|
/// Returns the new drawer model, plus the submitted command line (if any)
/// for the caller to execute — the drawer does not own the session log.
pub fn update(msg : Msg, model : Model) -> (Model, String?) {
  match msg {
    Toggle => ({ ..model, visible: !model.visible }, None)
    InputChanged(text) => ({ ..model, input: text }, None)
    Submit => {
      let line = model.input.trim().to_owned()
      if line == "" {
        (model, None)
      } else {
        ({ ..model, input: "" }, Some(line))
      }
    }
    KeyPressed(key) =>
      if key.code() == "Backquote" &&
        key.ctrl_key() &&
        !key.repeat() &&
        !key.is_composing() {
        ({ ..model, visible: !model.visible }, None)
      } else {
        (model, None)
      }
  }
}

///|
pub fn subscriptions(emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.on_key_down(key => emit(KeyPressed(key)))
}

///|
pub fn view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  // Conditional sibling rendered last in the page so toggling it never
  // shifts the index of earlier nodes. `autofocus` puts the cursor in the
  // input whenever the drawer mounts.
  if model.visible {
    @html.div(class="terminal-panel") <| [
      @html.input(
        class="terminal-input",
        placeholder="type a command",
        value=model.input,
        autofocus=true,
        on_input=emit.map(text => InputChanged(text)),
      ),
      @html.button(class="terminal-run", on_click=emit(Submit), "run"),
    ]
  } else {
    @html.nothing
  }
}
