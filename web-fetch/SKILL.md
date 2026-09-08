---
name: web-fetch
description: Fetch web pages and get their readable content (title + main text, optionally links) with a pure-MoonBit CLI built on moonbitlang/async HTTP and the moonbit-community/html WHATWG parser. Run it through moonx as `moonx tonyfettes/skills-web-fetch`. Use when you need to read a URL's content — static HTML, SSR pages, or JSON/text APIs. Do not use for pages whose content is rendered only by client-side JavaScript (no headless browser here), or when the deliverable is a scraped dataset rather than reading a page.
---

# web-fetch (tonyfettes/skills-web-fetch)

Fetch `http(s)://` URLs and print readable content. HTML pages are reduced to
their title and main text via a WHATWG-compliant parser; anything else
(JSON, text, XML) is printed raw. Redirects are followed; relative links are
resolved against the page URL.

Implementation: the CLI entry is `main.mbt` in the single top-level
executable package (`moon.pkg`, `pkgtype(kind: "executable")`); the logic lives
in module-internal packages below `internal/` (importable only inside this
module): `internal/fetch` (async HTTP, redirects, content-type sniffing),
`internal/extract` (html5 → title/text/links), `internal/url` (relative URL
resolution, shared by fetch and extract). Published on mooncakes.io as
`tonyfettes/skills-web-fetch`, it runs sandboxed through `moonx` on its wasm
target.

## Use This Skill For

- Reading the content of a documentation page, blog post, changelog, wiki,
  GitHub page, or any server-rendered site (SSR output parses fine).
- Checking a page's title/headings or pulling the absolute links it contains.
- Reading JSON or plain-text endpoints that a page or API returns.

Do not use it when:

- The page is a client-side-only app (React/Vue shell) — the fetched HTML has
  no content because MoonBit cannot execute the page's JavaScript. There is no
  CSR-detection heuristic in this tool, so it will happily print what the
  server actually sent: an empty shell. Recognize that situation yourself and
  fall back to the site's JSON API, or say a headless browser would be needed.
- You need a screenshot or full DOM after scripts run.

## Running (published package)

From anywhere, run the mooncakes package with moonx (the coordinate is the
module name; no `--` separator before its flags):

```text
moonx tonyfettes/skills-web-fetch <url>
moonx tonyfettes/skills-web-fetch --links <url>
moonx tonyfettes/skills-web-fetch --raw <url>
moonx tonyfettes/skills-web-fetch --text 20000 <url>
moonx tonyfettes/skills-web-fetch --help
```

Multiple URLs are printed one after another with a `== url ==` banner; pass
`--stdin` to also read one URL per line from stdin (the sandbox feeds stdin
through, e.g. `stdin=Text(...)`). Exit codes: `0` all pages printed, `1` at
least one page failed (each failure prints one `error: ...` line), `2` usage
error.

`moonx` pulls the module from mooncakes.io; the module must be **published**
first (`moon login` + `moon publish` from this repo). While developing
locally, run the same binary from the repo root with:

```text
moon run --target native . -- <url>
moon test                       # 5 unit tests across internal/* packages
moon cram test tests/cram       # offline CLI contract tests
moon build --target wasm        # what moonx will run
```

### Options

| option | meaning |
| --- | --- |
| `--raw` | print the raw response body instead of extracting text (default for non-HTML) |
| `--links` | also list absolute links found on HTML pages as `- label: url` |
| `--stdin` | additionally read one URL per line from stdin (blank lines ignored) |
| `--max <bytes>` | cap the response body size (default 2000000) |
| `--text <chars>` | cap extracted/printed text per page (default 400000) |
| `--ua <string>` | set the User-Agent header |
| `-h`, `--help` | usage text |

## Output Shape

Default HTML output:

```text
Title: Example Domain

# Example Domain

This domain is for use in documentation examples without needing permission. Avoid use in operations.
```

- Extraction starts at the first `<main>` or `<article>`; otherwise the whole
  `<body>` is used, so site chrome (`<nav>`, menus) is usually excluded.
- `<script>`, `<style>`, `<template>`, SVG, and friends are dropped; `<pre>`
  text keeps its formatting.
- Headings are marked `#`–`######`, list items are prefixed `- `, so the text
  reads like lightweight Markdown (it is not a faithful HTML→Markdown
  conversion).
- Non-HTML responses (JSON, text/plain, XML, or an HTML-looking body without
  an HTML content type) print their body as-is, truncated at `--text` chars
  with a trailing `[...]` marker.

## Errors and exit codes

- `0` — every requested page printed.
- `1` — at least one page failed; each failure prints one
  `error: ...` line, the rest are still attempted.
- `2` — usage error (bad option, no URL given).

Failure messages are plain: `error: HTTP 404 Not Found for <url>`, redirect
loops, non-UTF-8 bodies, and network/TLS failures are all reported with the
URL.

## Practical guidance

- Keep `--text` small when the page might be long and you only need an
  overview; raise it when you need full prose.
- Use `--links` to find the next hop instead of hand-parsing HTML.
- Use `--raw` only when you need the exact markup/JSON; prefer the default for
  reading.
- Bodies are decoded as UTF-8 only; legacy charsets (e.g. GBK, latin-1) come
  out mojibake — say so rather than pretending the text is accurate.
- Redirects are followed up to 10 hops (Location header resolution included).
- This is an anonymous fetcher: it sends no cookies or ambient credentials and
  performs no SSRF filtering — do not point it at private/internal URLs or
  anything that requires auth.
