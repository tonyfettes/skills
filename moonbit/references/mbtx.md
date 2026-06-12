# `.mbtx` Scripting Reference

MoonBit `.mbtx` is a single-file script format that runs without a surrounding
`moon.mod`/`moon.mod.json` or `moon.pkg`. Dependencies are declared inline in the script
and resolved by the toolchain.

Use this reference when replacing shell/Python automation with MoonBit scripts
or when working with existing `.mbtx` files.

## API Lookup Rule

This file intentionally does not hardcode package API calls.

Before writing or explaining a `.mbtx` script that uses library packages, the
agent MUST follow the API Lookup Rule in `SKILL.md`. Do not copy calls from old
scripts without checking the current `.mbti`.

## Shape Of A Script

Scripts use normal MoonBit top-level blocks. Inline imports go at the top:

```moonbit
///|
import {
  "package/name",
  "package/name/subpackage",
}

///|
async fn main {
  ...
}
```

Use `async fn main` only when the script depends on async packages. Import the
base async package when the current async package docs require it.

Run scripts with the native target when they use packages backed by native
runtime or C FFI:

```sh
moon run --target native script.mbtx -- arg1 arg2
```

Arguments after `--` are passed to the script.

## Common Script-Specific Checks

- Confirm import syntax from current `.mbtx` examples or parser behavior before
  editing many scripts.
- Confirm target support. Native, JS, and platform-specific packages differ.
- Confirm resource cleanup from README/tests/source instead of assuming a
  `finally`-style pattern.
- Confirm whether a helper creates missing files/directories, follows symlinks,
  inherits environment, or buffers output from the current interface and tests.
- Confirm regex syntax and JSON conversion behavior from current core package
  docs before writing parsing code.
