# tonyfettes/skills-deepseek-web-search

A tiny "web search" CLI written in pure MoonBit: run one native web search per
query through DeepSeek's Anthropic-compatible Messages API and print the
citeable sources the model should use. Sources arrive as a bounded markdown
list (`- [title](url) — snippet (date)`), deduped by URL and capped at a
consumer-chosen result limit.

It powers a SeekMoon-style "web search" skill; the module is a single top-level
executable package (root `moon.pkg`, `pkgtype(kind: "executable")`) with the
logic in a module-internal package:

```text
internal/search/    DeepSeek native-search client (Messages POST + block
                    parsing, dedupe, citation join, markdown formatting)
```

The searched sources arrive in two pieces that the module joins by URL: the
citeable items (`url`, `title`, `page_age`) live in `web_search_tool_result`
blocks, while the snippet for a URL is the `cited_text` of a `text` block's
citation entry. Sources are deduped by URL and cut to a result cap (default 8).

Only a DeepSeek API key is needed (the `DEEPSEEK` environment variable or
`--api-key`); no third-party search API.

## Running

Once published on mooncakes.io:

```text
moonx tonyfettes/skills-deepseek-web-search "MoonBit programming language"
moonx tonyfettes/skills-deepseek-web-search --max-results 5 "what is wasm"
moonx tonyfettes/skills-deepseek-web-search --api-key $DEEPSEEK "MoonBit"
moonx tonyfettes/skills-deepseek-web-search --help
```

Options: `--api-key <key>` (DeepSeek API key; default `$DEEPSEEK`),
`--base-url <url>` (Messages base, default `https://api.deepseek.com/anthropic/v1`),
`--model <name>` (default `deepseek-v4-flash`), `--max-results <n>` (source cap,
default 8), `--max-uses <n>` (native tool uses per query, default 5),
`--max-tokens <n>` (default 4096), `--timeout-ms <n>` (default 120000),
`--stdin` (read one query per line from stdin), `-h/--help`.

Exit codes: `0` every query searched and printed; `1` at least one query failed
(each failure prints one `error: ...` line); `2` usage error.

## Local development

```text
moon test                        # 11 offline unit tests + 1 opt-in realworld (needs $DEEPSEEK)
moon cram test tests/cram        # offline CLI usage contract
moon run --target native . -- "MoonBit programming language"
moon build --target wasm         # the artifact moonx runs
```

## Notes

- Each query costs an auxiliary DeepSeek model turn (native `web_search`
  server tool); the model's prose is discarded — only result blocks survive.
- Absence of `web_search_tool_result` blocks is reported as an error, not
  rendered as an empty result set: that is a provider misfire.
- Queries are capped at 2000 chars; a search call is wall-bounded by
  `--timeout-ms`.
- The CLI argument parser tolerates runners that pass `argv[0]` (native `moon
  run`) and those that do not (`moonx`).
