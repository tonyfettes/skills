///|
test "next_action pops the last pending job" {
  let pending = ["a", "b", "c"]
  @debug.assert_eq(@queue.next_action(pending), "run:c")
  @debug.assert_eq(pending, ["a", "b"])
  @debug.assert_eq(@queue.next_action([]), "idle")
}

///|
test "port_from: present, absent, invalid" {
  let env = { "PORT": "9090", "BAD": "x9" }
  @debug.assert_eq(@queue.port_from(env, "PORT"), 9090)
  @debug.assert_eq(@queue.port_from(env, "MISSING"), 8080)
  try @queue.port_from(env, "BAD") |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("invalid port value must raise")
  }
}
