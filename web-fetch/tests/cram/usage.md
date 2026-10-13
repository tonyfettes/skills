# CLI usage contract (offline)

Offline contract tests for `tonyfettes/skills-web-fetch`: help output, option
validation and exit codes. No network required; the fetch path itself is
covered by opt-in live tests under `tests/live/`.

## --help prints usage and exits 0

```mooncram
$ skills-web-fetch.exe --help
usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. HTML pages are reduced to their
title and main text; other responses are printed raw. Body size is capped
with --max so a huge download cannot flood the output.

options:
  --raw          print the raw response body instead of extracting text
  --links        also list absolute links found on HTML pages
  --stdin        additionally read one URL per line from stdin
  --max <bytes>  cap the response body size (default 2000000)
  --text <chars> cap extracted or printed text (default 400000)
  --ua <string>  set the User-Agent header
  -h, --help     show this help
```

## Unknown option prints an error plus usage and exits 2

```mooncram
$ skills-web-fetch.exe --bogus
skills-web-fetch: error: unknown option: --bogus

usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. HTML pages are reduced to their
title and main text; other responses are printed raw. Body size is capped
with --max so a huge download cannot flood the output.

options:
  --raw          print the raw response body instead of extracting text
  --links        also list absolute links found on HTML pages
  --stdin        additionally read one URL per line from stdin
  --max <bytes>  cap the response body size (default 2000000)
  --text <chars> cap extracted or printed text (default 400000)
  --ua <string>  set the User-Agent header
  -h, --help     show this help
[2]
```

## Missing URL prints an error plus usage and exits 2

```mooncram
$ skills-web-fetch.exe
skills-web-fetch: error: no URLs given

usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]

Fetch web pages and print their content. HTML pages are reduced to their
title and main text; other responses are printed raw. Body size is capped
with --max so a huge download cannot flood the output.

options:
  --raw          print the raw response body instead of extracting text
  --links        also list absolute links found on HTML pages
  --stdin        additionally read one URL per line from stdin
  --max <bytes>  cap the response body size (default 2000000)
  --text <chars> cap extracted or printed text (default 400000)
  --ua <string>  set the User-Agent header
  -h, --help     show this help
[2]
```
