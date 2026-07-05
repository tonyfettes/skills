This MoonBit project (native backend, `moonbitlang/async`) implements a session protocol on top of a connection.

Implement `with_session` in `session/session.mbt` according to its doc comment. The protocol requirement that matters most: the final `"END"` message must reach the connection in **every** case — normal completion, an error raised by `body`, and **cancellation** (callers routinely wrap a session in `@async.with_timeout`, which cancels it; a missing `"END"` locks the account on the peer side).

Do not modify `session/conn.mbt` (the grader restores it). Keep the public signature of `with_session` exactly as given.

The project must pass `moon check --target native` when you are done. You may add tests of your own.

Work only inside the current directory.
