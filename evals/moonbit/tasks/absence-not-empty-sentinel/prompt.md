This MoonBit project ingests telemetry events (see `events/events.mbt`).

Implement the two stub functions, defining the `Event` fields and any
supporting types yourself (keep the two public function signatures as given):

- `parse_event(json : Json) -> Event raise` — parse one event object.
  - Every event carries a required string field `id`.
  - An event may also carry a string field `trace`.
  - Anything else is malformed: a missing `id`, or an `id`/`trace` that is
    present but not a string, must fail parsing in a way callers can catch
    and handle programmatically.
- `trace_line(event : Event) -> String` — the log line for an event's trace:
  `trace=<value>` when the incoming event had a `trace` field, `trace=none`
  when it did not.

The project must pass `moon check` when you are done. You may add tests of
your own.

Work only inside the current directory.
