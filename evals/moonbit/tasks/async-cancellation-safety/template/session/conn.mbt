// Test double for a network connection. DO NOT MODIFY THIS FILE —
// the grader restores it before running, so changes here are discarded.

///|
/// A fake connection that records every message that was actually sent.
/// `send` suspends first (simulated network latency), like a real socket
/// write would.
pub struct Conn {
  priv log : Array[String]
}

///|
pub fn Conn::make() -> Conn {
  { log: [] }
}

///|
/// Messages sent so far, in order.
pub fn Conn::sent(self : Conn) -> Array[String] {
  self.log.copy()
}

///|
/// Send one message over the connection. Suspends before the message is
/// recorded — a suspension point, exactly like a real network write.
pub async fn Conn::send(self : Conn, msg : String) -> Unit {
  @async.sleep(5)
  self.log.push(msg)
}
