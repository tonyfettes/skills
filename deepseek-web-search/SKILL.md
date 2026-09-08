---
name: deepseek-web-search
description: Search the web for current information with a pure-MoonBit CLI that runs DeepSeek's native web search and returns a bounded, citeable source list (markdown `- [title](url) — snippet`). Run it through moonx as `moonx tonyfettes/skills-deepseek-web-search`. Use when the answer may have changed since your training data or lives outside the workspace — current releases, external docs, error messages you do not recognize. Needs a DeepSeek API key (`$DEEPSEEK` or `--api-key`).
---

# deepseek-web-search (tonyfettes/skills-deepseek-web-search)

Search the web and print a bounded, citeable source list. Each query runs one
native web search via DeepSeek's Anthropic-compatible Messages API
(`web_search_20250305` server tool); the output is the sources the model should
cite, rendered as markdown:

```text
Sources:
- [docs.moonbitlang.com](https://docs.moonbitlang.com/en/stable/...) — summary
- [MoonBit Language](https://docs.moonbitlang.com/en/stable/language/index.html)

(Showing the first 8 sources. Refine the query for more.)

Cite the relevant URLs above as markdown links in your answer.
```

Implementation: the CLI entry is `main.mbt` in the single top-level executable
package (`moon.pkg`, `pkgtype(kind: "executable")`); the logic lives in the
module-internal package `internal/search` (async HTTP Messages POST, result
block walking, URL dedupe, citation joining, markdown formatting). Published on
mooncakes.io as `tonyfettes/skills-deepseek-web-search`, it runs sandboxed through
`moonx` on its wasm target.

## Use This Skill For

- Searching for current information that may have changed since the model's
  training data or lives outside the workspace: current releases, external
  documentation, error messages, package registry entries, people, events.
- Getting a bounded set of source URLs to cite — the output is a citeable
  source list, not prose.

Do not use it when:

- A page's *content* is what you need (not a search): use `web-fetch` to read a
  specific URL's readable text.
- No DeepSeek API key is available (`$DEEPSEEK` unset and no `--api-key`): the
  CLI fails cleanly, it does not fall back to a keyless scraper.
- The question is answerable from context or local files — searching costs a
  model turn and adds latency.

## Running (published package)

From anywhere, run the mooncakes package with moonx (the coordinate is the
module name; no `--` separator before its flags):

```text
moonx tonyfettes/skills-deepseek-web-search "MoonBit programming language"
moonx tonyfettes/skills-deepseek-web-search --max-results 5 "what is wasm"
moonx tonyfettes/skills-deepseek-web-search --api-key $DEEPSEEK "MoonBit"
moonx tonyfettes/skills-deepseek-web-search --help
```

The key comes from the `DEEPSEEK` environment variable or `--api-key`.
Multiple queries are printed one after another with a `== query ==` banner;
pass `--stdin` to also read one query per line from stdin (the sandbox feeds
stdin through). Exit codes: `0` every query searched, `1` at least one query
failed (each failure prints one `error: ...` line), `2` usage error.

`moonx` pulls the module from mooncakes.io; the module must be **published**
first (`moon login` + `moon publish` from this repo). While developing
locally, run the same binary from the repo root with:

```text
moon run --target native . -- "MoonBit programming language"
moon test                     # 11 offline unit tests + 1 opt-in realworld (needs $DEEPSEEK)
moon build --target wasm      # what moonx will run
```

### Options

| option | meaning |
| --- | --- |
| `--api-key <key>` | DeepSeek API key (default: `$DEEPSEEK`) |
| `--base-url <url>` | Anthropic-compatible Messages base (default: DeepSeek `/anthropic/v1`) |
| `--model <name>` | auxiliary search model (default `deepseek-v4-flash`) |
| `--max-results <n>` | cap on sources per query (default 8) |
| `--max-uses <n>` | native `web_search` tool uses per query (default 5) |
| `--max-tokens <n>` | generated-token cap for the search call (default 4096) |
| `--timeout-ms <n>` | wall timeout for one search call (default 120000) |
| `--stdin` | additionally read one query per line from stdin |
| `-h`, `--help` | usage text |

## Output Shape

Success (one source with title + snippet + date, one without):

```text
Sources:
- [Example A](https://example.com/a) — MoonBit is a fast language. (January 5, 2026)
- [example.org](https://example.org/b)

Cite the relevant URLs above as markdown links in your answer.
```

- Sources are deduped by URL and cut to `--max-results`; a cut appends
  `(Showing the first N sources. Refine the query for more.)`.
- Title-less sources fall back to the URL's hostname as the link label.
- Provider text (titles, snippets, dates) is collapsed to one line, capped, and
  markdown-escaped so it cannot break the `- [label](url) — meta` line shape.
- A search that returns no results prints `No results found.` — but a response
  with **no result blocks at all** is reported as an error: that is a provider
  misfire, not an empty result.

## Errors and exit codes

- `0` — every query searched and printed.
- `1` — at least one query failed; each failure prints one `error: ...` line
  (DeepSeek API status, timeout, missing result blocks, network/TLS).
- `2` — usage error (unknown option, missing value, no query given, query over
  2000 chars).

## Practical guidance

- Independent questions should be issued as several separate searches in the
  same step — they run concurrently. Keep each query focused; the result cap
  favors precision over a kitchen-sink query.
- Cite the URLs the tool returns as markdown links in your answer — that is the
  point of the output shape.
- The tool sends the DeepSeek key to the configured `--base-url`; by default
  that is DeepSeek's own Anthropic-compatible endpoint. Do not point it at a
  URL you do not trust with the key.
- Real search results drift between runs: assert on the output *shape*, never
  on specific URLs, when testing.
