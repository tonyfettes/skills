///|
/// Run `body` inside a session on `conn`:
///
///   1. send "BEGIN" on the connection,
///   2. run `body`,
///   3. send "END" on the connection.
///
/// "END" MUST be sent in every case: normal completion, `body` raising an
/// error, and the session being cancelled (callers routinely wrap sessions
/// in `@async.with_timeout`). The peer treats a missing "END" as a protocol
/// violation and drops the account into a locked state.
///
/// Errors from `body` must still propagate to the caller.
pub async fn with_session(conn : Conn, body : async () -> Unit) -> Unit {
  ...
}
