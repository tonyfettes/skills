///|
test "port_of returns the registered port" {
  let reg = @registry.Registry::make([("db", 5432), ("web", 80)])
  @debug.assert_eq(reg.port_of("db"), 5432)
  @debug.assert_eq(reg.port_of("web"), 80)
}

///|
test "missing service raises an error naming the service" {
  let reg = @registry.Registry::make([("db", 5432)])
  try reg.port_of("cache") |> ignore catch {
    err => assert_true("\{err}".contains("cache"))
  } noraise {
    _ => fail("missing service must raise, not return a sentinel")
  }
}
