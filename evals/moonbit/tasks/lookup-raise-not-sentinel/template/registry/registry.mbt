///|
/// In-memory service registry mapping service names to ports.
pub struct Registry {
  priv ports : Map[String, Int]
}

///|
pub fn Registry::make(entries : Array[(String, Int)]) -> Registry {
  let ports : Map[String, Int] = {}
  for e in entries {
    ports[e.0] = e.1
  }
  { ports: ports }
}
