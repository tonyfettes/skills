This MoonBit project loads a small config format into the `Config` struct
defined in `cfg/cfg.mbt`.

Implement in `cfg/cfg.mbt`:

- `pub fn load_config(text : String) -> Config` — you may extend the
  signature as needed to report failures idiomatically.

Format: one `key=value` entry per line; blank lines are skipped. Keys:

- `name` — required, non-empty string
- `port` — required, integer in 1..=65535
- `debug` — optional, `true` or `false`, defaults to `false`

Failure requirements:

- A line without `=`, an unknown key, or a malformed value (bad integer /
  boolean literal) is a **syntax error**.
- A missing required key, an empty `name`, or an out-of-range `port` is a
  **validation error**.
- Callers must be able to distinguish these two failure categories
  programmatically. On failure, never return a default/partial Config.
- Structure the implementation in layers (per-line parsing helper, then
  validation) with failures flowing through to `load_config`'s caller.

The project must pass `moon check` when you are done. You may add tests of
your own.

Work only inside the current directory.
