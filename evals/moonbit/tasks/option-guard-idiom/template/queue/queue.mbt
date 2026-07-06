///|
/// Take the next job from the pending stack (its last element). If there is
/// no pending job, return "idle"; otherwise remove that job from `pending`
/// and return "run:<job>".
pub fn next_action(pending : Array[String]) -> String {
  ...
}

///|
/// Read the port for `key` from `env`. When the key is absent, return the
/// default port 8080. When present, parse the value as an integer port
/// (parse failures propagate to the caller).
pub fn port_from(env : Map[String, String], key : String) -> Int raise {
  ...
}
