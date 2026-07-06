This MoonBit project schedules jobs from a pending stack.

Implement the two stub functions in `queue/queue.mbt` exactly as their doc
comments describe:

- `next_action(pending : Array[String]) -> String` — pop the last pending job
  and return `"run:<job>"`, or `"idle"` when there is none.
- `port_from(env : Map[String, String], key : String) -> Int raise` — the
  configured port, or the default 8080 when `key` is absent; invalid values
  propagate a parse failure.

Requirements:

- Keep the public signatures exactly as given.
- Write idiomatic MoonBit.
- The project must pass `moon check` when you are done. You may add tests of
  your own.

Work only inside the current directory.
