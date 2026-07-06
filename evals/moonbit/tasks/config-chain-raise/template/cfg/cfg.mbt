///|
/// Parsed configuration. See the project README/prompt for the text format.
pub(all) struct Config {
  name : String
  port : Int
  debug : Bool
} derive(Debug, Eq)
