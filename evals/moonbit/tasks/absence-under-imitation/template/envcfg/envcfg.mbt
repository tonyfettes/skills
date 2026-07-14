///|
/// Raw text of `key` in the environment snapshot, or "" when unset.
pub fn raw_value(env : Map[String, String], key : String) -> String {
  env.get(key).unwrap_or("")
}

///|
/// Directory listed first in PATH, or "" when PATH is unset.
pub fn first_path_dir(env : Map[String, String]) -> String {
  let path = raw_value(env, "PATH")
  if path == "" {
    return ""
  }
  match path.split(":").collect() {
    [first, ..] => first.to_owned()
    [] => ""
  }
}
