///|
/// Parsed command line for the `mgrep` tool.
pub(all) struct CliConfig {
  verbose : Bool
  output : String?
  patterns : Array[String]
} derive(Debug, Eq)

///|
/// Parse `argv` (the arguments after the program name) into a `CliConfig`.
/// See the task prompt for the accepted grammar.
pub fn parse_cli(argv : Array[String]) -> CliConfig raise {
  ...
}
