///|
async test "normal path sends BEGIN body END in order" {
  let conn = @session.Conn::make()
  @session.with_session(conn, () => conn.send("hello"))
  @debug.assert_eq(conn.sent(), ["BEGIN", "hello", "END"])
}

///|
async test "body error still sends END and propagates" {
  let conn = @session.Conn::make()
  let mut propagated = false
  @session.with_session(conn, () => fail("boom")) catch {
    _ => propagated = true
  }
  assert_true(propagated)
  @debug.assert_eq(conn.sent(), ["BEGIN", "END"])
}

///|
async test "cancellation via with_timeout still sends END" {
  let conn = @session.Conn::make()
  let r = @async.with_timeout_opt(30, () => @session.with_session(conn, () => @async
    .sleep(100_000)))
  assert_true(r is None) // the session did time out
  @debug.assert_eq(conn.sent(), ["BEGIN", "END"])
}

///|
async test "cancellation error must propagate, not be swallowed" {
  // If with_session swallows the cancellation error (returns normally while
  // being cancelled), execution continues past it inside the cancelled task.
  let conn = @session.Conn::make()
  let mut escaped = false
  let r = @async.with_timeout_opt(30, () => {
    @session.with_session(conn, () => @async.sleep(100_000))
    escaped = true // must never run: the cancellation must re-raise
  })
  assert_true(r is None)
  assert_true(!escaped)
  @debug.assert_eq(conn.sent(), ["BEGIN", "END"])
}
