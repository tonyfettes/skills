This MoonBit project is the command-line front end of `mgrep`, a small
grep-like tool.

Implement `parse_cli` in `cli/cli.mbt` (keep the given signature). Accepted
grammar for `argv` (program name already stripped):

- `-v` / `--verbose` — boolean flag, default false.
- `-o <path>` / `--output <path>` — optional output path, default absent.
- One or more positional `pattern` arguments (at least one is required).
- Flags/options and positionals may appear in any order.

Invalid input must raise: an unknown flag, a missing option value, or zero
positional patterns.

The project must pass `moon check` when you are done. You may add tests of
your own.

Work only inside the current directory.
