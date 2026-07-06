# MoonBit CLI Programs

Command-line argument parsing with the stdlib `@argparse`, plus process
arguments and environment variables via `@env`. All verified with moon
0.1.20260629.

## Argument parsing: `@argparse` (stdlib — never hand-roll an argv loop)

`moonbitlang/core/argparse` ships with the stdlib (no external dependency)
and is the first choice for CLI parsing. It is declarative, clap-style:
describe the command, then read typed results from `Matches`.

```mbt nocheck
// moon.pkg: import { "moonbitlang/core/argparse" }
let cmd = @argparse.Command(
  "mytool",
  flags=[@argparse.FlagArg("verbose", short='v', long="verbose")],
  options=[@argparse.OptionArg("output", short='o', long="output")],
  positionals=[
    @argparse.PositionArg("patterns", num_args=@argparse.ValueRange(lower=1)),
  ],
)
let m = cmd.parse(argv=args[:])       // -> Matches raise
let verbose = m.flags.get("verbose").unwrap_or(false)
let output = m.values.get("output").map(vs => vs[0])
let patterns = m.values.get("patterns").unwrap_or([])
```

- `Command::parse(argv? : ArrayView[String], env? : Map[String, String]) -> Matches raise`
  **raises** on invalid input — unknown flags, missing option values, arity
  violations (e.g. `ValueRange(lower=1)` rejects zero positionals). Let the
  error propagate or catch it to print usage; do not pre-validate by hand.
- Read results from `Matches.flags : Map[String, Bool]` and
  `Matches.values : Map[String, Array[String]]` (options and positionals both
  land in `values`).
- Also available (see `moon ide doc "@argparse"` for signatures): subcommands
  (`Command(subcommands=[...])`, results in `Matches.subcommand`), env-var
  fallbacks (`env=` on args), default values, arg groups
  (`requires`/`conflicts_with`), auto `--help`/`--version`.

## Process arguments and environment: `@env`

`moonbitlang/core/env`:

```mbt nocheck
let argv : Array[String] = @env.args()
let home : String? = @env.get_env_var("HOME")
```

Prefer these over `moonbitlang/x/sys` duplicates (`get_cli_args`, ...) — the
`x` package predates the core equivalents (see the `moonbitlang/x` rule in
`SKILL.md`).
