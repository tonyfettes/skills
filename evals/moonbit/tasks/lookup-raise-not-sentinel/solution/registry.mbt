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

///|
pub suberror ServiceNotFound {
  ServiceNotFound(String)
} derive(Debug)

///|
pub impl Show for ServiceNotFound with output(self, logger) {
  let ServiceNotFound(name) = self
  logger.write_string("service not found: \{name}")
}

///|
/// Port registered for `name`. Raises `ServiceNotFound` when the service is
/// not registered.
pub fn Registry::port_of(self : Registry, name : String) -> Int raise ServiceNotFound {
  guard self.ports.get(name) is Some(port) else {
    raise ServiceNotFound(name)
  }
  port
}
