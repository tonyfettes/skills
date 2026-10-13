# tonyfettes/skills-web-fetch

A tiny "web fetch" CLI written in pure MoonBit: fetch an `http(s)://` URL and
print what an agent actually wants to read. HTML pages are reduced to their
title and main text via the WHATWG-compliant `moonbit-community/html` parser;
JSON / text / XML responses are printed raw. Redirects (up to 10) are followed
and relative links are resolved against the final URL.

It powers a SeekMoon-style "web fetch" skill; the module is a single top-level
executable package (root `moon.pkg`) with the logic split into module-internal
packages:

```text
internal/fetch/     HTTP(S) fetch, redirects, content-type sniffing
internal/extract/   HTML5 → title / readable text / absolute links
internal/url/       relative URL resolution (shared)
```

Static and server-side-rendered pages work out of the box. Client-side-only
apps (React/Vue shells whose HTML contains no content) are out of scope — no
JavaScript engine or headless browser is involved.

## Running

Once published on mooncakes.io:

```text
moonx tonyfettes/skills-web-fetch https://example.com/
moonx tonyfettes/skills-web-fetch --links https://example.com/
moonx tonyfettes/skills-web-fetch --raw https://example.com/
moonx tonyfettes/skills-web-fetch --help
```

Options: `--raw` (print the body verbatim), `--links` (also list absolute
links as `- label: url`), `--stdin` (read one URL per line from stdin),
`--max <bytes>` (body size cap, default 2_000_000), `--text <chars>` (output
cap per page, default 400_000), `--ua <string>`, `-h/--help`.

Exit codes: `0` everything printed; `1` at least one page failed (each failure
prints one `error: ...` line); `2` usage error.

## Named script (SeekMoon / OpenSeek)

An agent can call the committed `scripts/fetch.mbtx` instead of writing an
inline `moonx` wrapper; it forwards every argument, and the CLI's exit status,
unchanged. The path resolves from the agent's workspace root, so it is
`web-fetch/scripts/fetch.mbtx` when that root is a checkout of this repository:

```text
mbtx(filename="scripts/fetch.mbtx", args=["https://example.com/"])
mbtx(filename="web-fetch/scripts/fetch.mbtx", args=["https://example.com/"])
```

## Local development

```text
moon test                 # 5 unit tests across the internal packages
moon run --target native . -- https://example.com/
moon build --target wasm  # the artifact moonx runs
```

## Notes

- Bodies are decoded as UTF-8 only; legacy charsets (GBK, latin-1 …) come out
  mojibake.
- The fetcher sends no cookies or ambient credentials and performs no SSRF
  filtering — do not point it at private/internal URLs.
- CLI argument parsing tolerates runners that pass `argv[0]` (native `moon
  run`) and those that do not (`moonx`).
