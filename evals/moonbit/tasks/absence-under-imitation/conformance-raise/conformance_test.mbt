///|
test "configured editor is reported" {
  @debug.assert_eq(@envcfg.editor_command({ "EDITOR": "vim" }), "vim")
}

///|
test "unset editor fails instead of fabricating a command" {
  try @envcfg.editor_command(Map([])) |> ignore catch {
    _ => ()
  } noraise {
    cmd => fail("expected a failure for an unset EDITOR, got \{cmd}")
  }
}
