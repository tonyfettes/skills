///|
test "id and trace parse through" {
  let json : Json = { "id": "e1", "trace": "abc123" }
  let ev = @events.parse_event(json)
  @debug.assert_eq(@events.trace_line(ev), "trace=abc123")
}

///|
test "absent trace renders none" {
  let json : Json = { "id": "e1" }
  let ev = @events.parse_event(json)
  @debug.assert_eq(@events.trace_line(ev), "trace=none")
}

///|
test "empty-but-present trace is distinct from absent" {
  let json : Json = { "id": "e1", "trace": "" }
  let ev = @events.parse_event(json)
  @debug.assert_eq(@events.trace_line(ev), "trace=")
}

///|
test "missing id fails parsing" {
  let json : Json = { "trace": "abc" }
  try @events.parse_event(json) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("missing id must fail parsing, not default")
  }
}

///|
test "non-string trace fails parsing" {
  let json : Json = { "id": "e1", "trace": 42 }
  try @events.parse_event(json) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("non-string trace must fail parsing, not be dropped")
  }
}
