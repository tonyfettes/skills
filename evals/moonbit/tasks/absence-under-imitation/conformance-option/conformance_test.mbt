///|
test "configured editor is reported" {
  @debug.assert_eq(@envcfg.editor_command({ "EDITOR": "vim" }), Some("vim"))
}

///|
test "unset editor is reported as absent" {
  @debug.assert_eq(@envcfg.editor_command(Map([])), None)
}
