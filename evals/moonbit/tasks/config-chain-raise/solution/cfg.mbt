///|
/// Parsed configuration. See the project README/prompt for the text format.
pub(all) struct Config {
  name : String
  port : Int
  debug : Bool
} derive(Debug, Eq)

///|
pub suberror SyntaxError {
  MissingEquals(String)
  UnknownKey(String)
  BadValue(key~ : String, String)
} derive(Debug)

///|
pub suberror ValidationError {
  MissingKey(String)
  EmptyName
  PortOutOfRange(Int)
} derive(Debug)

///|
priv struct Partial {
  mut name : String?
  mut port : Int?
  mut debug : Bool
}

///|
fn parse_line(acc : Partial, line : String) -> Unit raise SyntaxError {
  guard line.find("=") is Some(eq) else { raise MissingEquals(line) }
  let key = line.view(end_offset=eq).to_owned()
  let value = line.view(start_offset=eq + 1).to_owned()
  match key {
    "name" => acc.name = Some(value)
    "port" =>
      acc.port = Some(
        @str.parse_int(value) catch {
          _ => raise BadValue(key~, value)
        },
      )
    "debug" =>
      acc.debug = match value {
        "true" => true
        "false" => false
        _ => raise BadValue(key~, value)
      }
    _ => raise UnknownKey(key)
  }
}

///|
fn validate(acc : Partial) -> Config raise ValidationError {
  guard acc.name is Some(name) else { raise MissingKey("name") }
  guard name is [_, ..] else { raise EmptyName }
  guard acc.port is Some(port) else { raise MissingKey("port") }
  guard port >= 1 && port <= 65535 else { raise PortOutOfRange(port) }
  { name, port, debug: acc.debug }
}

///|
/// Load a Config from `text`. Raises `SyntaxError` for malformed input and
/// `ValidationError` for well-formed but invalid configurations.
pub fn load_config(text : String) -> Config raise {
  let acc : Partial = { name: None, port: None, debug: false }
  for line in text.split("\n") {
    if line is "" {
      continue
    }
    parse_line(acc, line.to_owned())
  }
  validate(acc)
}
