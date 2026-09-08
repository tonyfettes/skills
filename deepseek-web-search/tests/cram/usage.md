# CLI usage contract (offline)

Offline contract tests for `tonyfettes/skills-deepseek-web-search`: help output, option
validation and exit codes. No network required; the search path itself is
covered by opt-in live tests under `tests/live/`.

## --help prints usage and exits 0

```mooncram
$ skills-deepseek-web-search.exe --help
usage: moonx tonyfettes/skills-deepseek-web-search [options] <query> [...]

Search the web through DeepSeek's native web search and print a bounded,
citeable source list. The DeepSeek API key comes from the DEEPSEEK
environment variable or --api-key.

options:
  --api-key <key>     DeepSeek API key (default: $DEEPSEEK)
  --base-url <url>    Anthropic-compatible Messages base (default: DeepSeek /anthropic/v1)
  --model <name>      auxiliary search model (default: deepseek-v4-flash)
  --max-results <n>   cap on sources per query (default 8)
  --max-uses <n>      native web_search tool uses per query (default 5)
  --max-tokens <n>    generated-token cap for the search call (default 4096)
  --timeout-ms <n>    wall timeout for one search call (default 120000)
  --stdin             additionally read one query per line from stdin
  -h, --help          show this help
```

## Unknown option prints an error plus usage and exits 2

```mooncram
$ skills-deepseek-web-search.exe --bogus
skills-deepseek-web-search: error: unknown option: --bogus

usage: moonx tonyfettes/skills-deepseek-web-search [options] <query> [...]

Search the web through DeepSeek's native web search and print a bounded,
citeable source list. The DeepSeek API key comes from the DEEPSEEK
environment variable or --api-key.

options:
  --api-key <key>     DeepSeek API key (default: $DEEPSEEK)
  --base-url <url>    Anthropic-compatible Messages base (default: DeepSeek /anthropic/v1)
  --model <name>      auxiliary search model (default: deepseek-v4-flash)
  --max-results <n>   cap on sources per query (default 8)
  --max-uses <n>      native web_search tool uses per query (default 5)
  --max-tokens <n>    generated-token cap for the search call (default 4096)
  --timeout-ms <n>    wall timeout for one search call (default 120000)
  --stdin             additionally read one query per line from stdin
  -h, --help          show this help
[2]
```

## Missing query prints an error plus usage and exits 2

```mooncram
$ skills-deepseek-web-search.exe
skills-deepseek-web-search: error: no queries given

usage: moonx tonyfettes/skills-deepseek-web-search [options] <query> [...]

Search the web through DeepSeek's native web search and print a bounded,
citeable source list. The DeepSeek API key comes from the DEEPSEEK
environment variable or --api-key.

options:
  --api-key <key>     DeepSeek API key (default: $DEEPSEEK)
  --base-url <url>    Anthropic-compatible Messages base (default: DeepSeek /anthropic/v1)
  --model <name>      auxiliary search model (default: deepseek-v4-flash)
  --max-results <n>   cap on sources per query (default 8)
  --max-uses <n>      native web_search tool uses per query (default 5)
  --max-tokens <n>    generated-token cap for the search call (default 4096)
  --timeout-ms <n>    wall timeout for one search call (default 120000)
  --stdin             additionally read one query per line from stdin
  -h, --help          show this help
[2]
```

## Bad integer option prints an error plus usage and exits 2

```mooncram
$ skills-deepseek-web-search.exe --max-results nope moonbit
skills-deepseek-web-search: error: invalid --max-results value: nope

usage: moonx tonyfettes/skills-deepseek-web-search [options] <query> [...]

Search the web through DeepSeek's native web search and print a bounded,
citeable source list. The DeepSeek API key comes from the DEEPSEEK
environment variable or --api-key.

options:
  --api-key <key>     DeepSeek API key (default: $DEEPSEEK)
  --base-url <url>    Anthropic-compatible Messages base (default: DeepSeek /anthropic/v1)
  --model <name>      auxiliary search model (default: deepseek-v4-flash)
  --max-results <n>   cap on sources per query (default 8)
  --max-uses <n>      native web_search tool uses per query (default 5)
  --max-tokens <n>    generated-token cap for the search call (default 4096)
  --timeout-ms <n>    wall timeout for one search call (default 120000)
  --stdin             additionally read one query per line from stdin
  -h, --help          show this help
[2]
```
