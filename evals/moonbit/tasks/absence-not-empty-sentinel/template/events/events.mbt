///|
/// One ingested telemetry event. Define the fields yourself — whatever
/// `parse_event` and `trace_line` need.
pub struct Event {}

///|
/// Parse one telemetry event from its JSON form. See the task prompt for the
/// event format and failure requirements.
pub fn parse_event(json : Json) -> Event raise {
  ...
}

///|
/// Log line for an event's trace. See the task prompt for the exact
/// rendering rules.
pub fn trace_line(event : Event) -> String {
  ...
}
