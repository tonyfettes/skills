///|
/// One ingested telemetry event.
pub struct Event {
  id : String
  trace : String?
}

///|
pub suberror MalformedEvent {
  MalformedEvent(field~ : String)
} derive(Debug)

///|
pub impl Show for MalformedEvent with output(self, logger) {
  let MalformedEvent(field~) = self
  logger.write_string("malformed event: bad field \{field}")
}

///|
/// Parse one telemetry event from its JSON form. See the task prompt for the
/// event format and failure requirements.
pub fn parse_event(json : Json) -> Event raise {
  guard json is Object(obj) else { raise MalformedEvent(field="id") }
  guard obj.get("id") is Some(String(id)) else {
    raise MalformedEvent(field="id")
  }
  let trace = match obj.get("trace") {
    None => None
    Some(String(t)) => Some(t)
    Some(_) => raise MalformedEvent(field="trace")
  }
  { id, trace }
}

///|
/// Log line for an event's trace. See the task prompt for the exact
/// rendering rules.
pub fn trace_line(event : Event) -> String {
  if event.trace is Some(t) {
    "trace=\{t}"
  } else {
    "trace=none"
  }
}
