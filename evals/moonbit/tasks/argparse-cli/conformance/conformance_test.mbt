///|
fn expect_failure(f : () -> @cli.CliConfig raise) -> Bool {
  try f() |> ignore catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "short flags with option value" {
  let c = @cli.parse_cli(["-v", "-o", "out.txt", "foo", "bar"])
  @debug.assert_eq(c, {
    verbose: true,
    output: Some("out.txt"),
    patterns: ["foo", "bar"],
  })
}

///|
test "long forms" {
  let c = @cli.parse_cli(["--verbose", "--output", "x.log", "p1"])
  @debug.assert_eq(c, { verbose: true, output: Some("x.log"), patterns: ["p1"] })
}

///|
test "defaults" {
  let c = @cli.parse_cli(["p1", "p2", "p3"])
  @debug.assert_eq(c, { verbose: false, output: None, patterns: ["p1", "p2", "p3"] })
}

///|
test "invalid input raises" {
  assert_true(expect_failure(() => @cli.parse_cli(["--wat", "p"])))
  assert_true(expect_failure(() => @cli.parse_cli(["p", "-o"])))
  assert_true(expect_failure(() => @cli.parse_cli([])))
  assert_true(expect_failure(() => @cli.parse_cli(["-v", "-o", "x"])))
}
