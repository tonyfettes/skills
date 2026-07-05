///|
/// Run `body` inside a session on `conn`. See template doc comment.
pub async fn with_session(conn : Conn, body : async () -> Unit) -> Unit {
  conn.send("BEGIN")
  try body() catch {
    err => {
      if @async.is_being_cancelled() {
        // Cancellation kills async cleanup at the next suspension point,
        // so the END send must be shielded — bounded by its own timeout.
        try @async.protect_from_cancel(() => @async.with_timeout(
            1000,
            () => conn.send("END"),
          ))
        catch {
          // Cleanup failure must not mask the original error.
          _ => ()
        }
      } else {
        conn.send("END")
      }
      raise err
    }
  } noraise {
    _ => conn.send("END")
  }
}
