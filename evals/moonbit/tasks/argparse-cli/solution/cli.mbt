///|
/// Parsed command line for the `mgrep` tool.
pub(all) struct CliConfig {
  verbose : Bool
  output : String?
  patterns : Array[String]
} derive(Debug, Eq)

///|
/// Parse `argv` (the arguments after the program name) into a `CliConfig`.
pub fn parse_cli(argv : Array[String]) -> CliConfig raise {
  let cmd = @argparse.Command(
    "mgrep",
    flags=[@argparse.FlagArg("verbose", short='v', long="verbose")],
    options=[@argparse.OptionArg("output", short='o', long="output")],
    positionals=[
      @argparse.PositionArg("patterns", num_args=@argparse.ValueRange(lower=1)),
    ],
  )
  let m = cmd.parse(argv=argv[:])
  {
    verbose: m.flags.get("verbose").unwrap_or(false),
    output: m.values.get("output").map(vs => vs[0]),
    patterns: m.values.get("patterns").unwrap_or([]),
  }
}
