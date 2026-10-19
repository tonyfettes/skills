# CLI usage contract (offline)

Offline contract tests for `tonyfettes/skills-web-fetch`: help output, option
validation and exit codes. No network required and no API key needed; the
fetch paths themselves are covered by opt-in live tests under `tests/live/`.

## --help prints usage and exits 0

```mooncram
$ skills-web-fetch.exe --help
usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. With a DeepSeek API key the page
comes from the DeepSeek Fetch API as Markdown; otherwise a local fetch
reduces HTML to its title and main text and prints other responses raw.

options:
  --backend <name>  auto (default), deepseek, or local
  --api-key <key>   DeepSeek API key (default: $DEEPSEEK, then
                    $DEEPSEEK_API_KEY)
  --base-url <url>  DeepSeek API base (default https://api.deepseek.com)
  --raw             print the raw response body instead of extracting text
                    (local backend only; implies --backend local)
  --links           also list the absolute links a page contains
  --stdin           additionally read one URL per line from stdin
  --max <bytes>     cap the local response body size (default 2000000)
  --text <chars>    cap extracted or printed text (default 400000)
  --ua <string>     set the User-Agent header of the local fetcher
  -h, --help        show this help
```

## Unknown option prints an error plus usage and exits 2

```mooncram
$ skills-web-fetch.exe --bogus
skills-web-fetch: error: unknown option: --bogus

usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. With a DeepSeek API key the page
comes from the DeepSeek Fetch API as Markdown; otherwise a local fetch
reduces HTML to its title and main text and prints other responses raw.

options:
  --backend <name>  auto (default), deepseek, or local
  --api-key <key>   DeepSeek API key (default: $DEEPSEEK, then
                    $DEEPSEEK_API_KEY)
  --base-url <url>  DeepSeek API base (default https://api.deepseek.com)
  --raw             print the raw response body instead of extracting text
                    (local backend only; implies --backend local)
  --links           also list the absolute links a page contains
  --stdin           additionally read one URL per line from stdin
  --max <bytes>     cap the local response body size (default 2000000)
  --text <chars>    cap extracted or printed text (default 400000)
  --ua <string>     set the User-Agent header of the local fetcher
  -h, --help        show this help
[2]
```

## Unknown backend name is a usage error

```mooncram
$ skills-web-fetch.exe --backend bogus https://example.com/
skills-web-fetch: error: unknown backend: bogus (expected auto, deepseek, or local)

usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. With a DeepSeek API key the page
comes from the DeepSeek Fetch API as Markdown; otherwise a local fetch
reduces HTML to its title and main text and prints other responses raw.

options:
  --backend <name>  auto (default), deepseek, or local
  --api-key <key>   DeepSeek API key (default: $DEEPSEEK, then
                    $DEEPSEEK_API_KEY)
  --base-url <url>  DeepSeek API base (default https://api.deepseek.com)
  --raw             print the raw response body instead of extracting text
                    (local backend only; implies --backend local)
  --links           also list the absolute links a page contains
  --stdin           additionally read one URL per line from stdin
  --max <bytes>     cap the local response body size (default 2000000)
  --text <chars>    cap extracted or printed text (default 400000)
  --ua <string>     set the User-Agent header of the local fetcher
  -h, --help        show this help
[2]
```

## --raw cannot be combined with the DeepSeek backend

The DeepSeek Fetch API returns Markdown, never the response bytes, so asking
for both is refused instead of silently downgrading the request.

```mooncram
$ skills-web-fetch.exe --raw --backend deepseek https://example.com/
skills-web-fetch: error: --raw prints the raw response body, which the DeepSeek backend does not return; use --backend local

usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. With a DeepSeek API key the page
comes from the DeepSeek Fetch API as Markdown; otherwise a local fetch
reduces HTML to its title and main text and prints other responses raw.

options:
  --backend <name>  auto (default), deepseek, or local
  --api-key <key>   DeepSeek API key (default: $DEEPSEEK, then
                    $DEEPSEEK_API_KEY)
  --base-url <url>  DeepSeek API base (default https://api.deepseek.com)
  --raw             print the raw response body instead of extracting text
                    (local backend only; implies --backend local)
  --links           also list the absolute links a page contains
  --stdin           additionally read one URL per line from stdin
  --max <bytes>     cap the local response body size (default 2000000)
  --text <chars>    cap extracted or printed text (default 400000)
  --ua <string>     set the User-Agent header of the local fetcher
  -h, --help        show this help
[2]
```

## A missing value for an option is a usage error

```mooncram
$ skills-web-fetch.exe --backend
skills-web-fetch: error: missing value for --backend

usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. With a DeepSeek API key the page
comes from the DeepSeek Fetch API as Markdown; otherwise a local fetch
reduces HTML to its title and main text and prints other responses raw.

options:
  --backend <name>  auto (default), deepseek, or local
  --api-key <key>   DeepSeek API key (default: $DEEPSEEK, then
                    $DEEPSEEK_API_KEY)
  --base-url <url>  DeepSeek API base (default https://api.deepseek.com)
  --raw             print the raw response body instead of extracting text
                    (local backend only; implies --backend local)
  --links           also list the absolute links a page contains
  --stdin           additionally read one URL per line from stdin
  --max <bytes>     cap the local response body size (default 2000000)
  --text <chars>    cap extracted or printed text (default 400000)
  --ua <string>     set the User-Agent header of the local fetcher
  -h, --help        show this help
[2]
```

## Missing URL prints an error plus usage and exits 2

```mooncram
$ skills-web-fetch.exe
skills-web-fetch: error: no URLs given

usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. With a DeepSeek API key the page
comes from the DeepSeek Fetch API as Markdown; otherwise a local fetch
reduces HTML to its title and main text and prints other responses raw.

options:
  --backend <name>  auto (default), deepseek, or local
  --api-key <key>   DeepSeek API key (default: $DEEPSEEK, then
                    $DEEPSEEK_API_KEY)
  --base-url <url>  DeepSeek API base (default https://api.deepseek.com)
  --raw             print the raw response body instead of extracting text
                    (local backend only; implies --backend local)
  --links           also list the absolute links a page contains
  --stdin           additionally read one URL per line from stdin
  --max <bytes>     cap the local response body size (default 2000000)
  --text <chars>    cap extracted or printed text (default 400000)
  --ua <string>     set the User-Agent header of the local fetcher
  -h, --help        show this help
[2]
```

## The DeepSeek backend rejects a URL the API would reject, before spending a request

Validation happens in-process, so this case needs no network and no valid key.

```mooncram
$ skills-web-fetch.exe --backend deepseek --api-key placeholder https:///nohost
error: URL must contain a host for https:///nohost
[1]
```

```mooncram
$ skills-web-fetch.exe --backend deepseek --api-key placeholder https://user:pw@example.com/
error: URL must not contain a username or password for https://user:pw@example.com/
[1]
```
