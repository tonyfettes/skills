///|
fn expect_failure(f : () -> @cfg.Config raise) -> Bool {
  try f() |> ignore catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "well-formed config loads" {
  let c = @cfg.load_config("name=api\nport=8080\ndebug=true")
  @debug.assert_eq(c, { name: "api", port: 8080, debug: true })
}

///|
test "debug defaults to false and blank lines are skipped" {
  let c = @cfg.load_config("name=api\n\nport=80\n")
  @debug.assert_eq(c, { name: "api", port: 80, debug: false })
}

///|
test "syntax errors raise" {
  assert_true(expect_failure(() => @cfg.load_config("name api\nport=80")))
  assert_true(expect_failure(() => @cfg.load_config("name=api\nport=eighty")))
  assert_true(expect_failure(() => @cfg.load_config("name=api\nport=80\nwat=1")))
  assert_true(expect_failure(() => @cfg.load_config("name=api\nport=80\ndebug=yes")))
}

///|
test "validation errors raise" {
  assert_true(expect_failure(() => @cfg.load_config("port=80")))
  assert_true(expect_failure(() => @cfg.load_config("name=api")))
  assert_true(expect_failure(() => @cfg.load_config("name=\nport=80")))
  assert_true(expect_failure(() => @cfg.load_config("name=api\nport=99999")))
  assert_true(expect_failure(() => @cfg.load_config("name=api\nport=0")))
}
