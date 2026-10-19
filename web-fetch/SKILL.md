---
name: web-fetch
description: Fetch web pages and get their readable content (title + Markdown body, optionally links) — through DeepSeek's Fetch API when a `$DEEPSEEK` key is available, otherwise with a pure-MoonBit local fetcher. Run it through moonx as `moonx tonyfettes/skills-web-fetch`. Use when you need to read a URL's content — static HTML, SSR pages, or JSON/text APIs (pass `--backend local` to keep those byte-exact). Do not use for pages whose content is rendered only by client-side JavaScript (no headless browser here), or when the deliverable is a scraped dataset rather than reading a page.
---

# web-fetch (tonyfettes/skills-web-fetch)

Fetch `http(s)://` URLs and print readable content: a `Title:` line, then the
page as Markdown. Two backends produce that same output shape:

- **DeepSeek Fetch** — `POST https://api.deepseek.com/v1/tools/fetch` returns
  the page already rendered as Markdown, with DeepSeek's own extractor doing
  the work. Needs an API key and is billed per successful request.
- **Local** — pure-MoonBit async HTTP plus the WHATWG `moonbit-community/html`
  parser: redirects are followed, relative links resolved, HTML reduced to its
  title and main text. No key, no cost, no third party.

`--backend auto` (the default) uses DeepSeek Fetch when a key resolves and the
local fetcher when it does not; `--backend deepseek` and `--backend local`
force one.

Implementation: the CLI entry is `main.mbt` in the single top-level executable
package (`moon.pkg`, `pkgtype(kind: "executable")`); the logic lives in
module-internal packages below `internal/` (importable only inside this
module): `internal/deepseek` (Fetch API client, error mapping, Markdown link
extraction), `internal/fetch` (local async HTTP, redirects, content-type
sniffing), `internal/extract` (html5 → title/text/links), `internal/url`
(relative URL resolution, shared by fetch and extract). Published on
mooncakes.io as `tonyfettes/skills-web-fetch`, it runs sandboxed through
`moonx` on its wasm target.

## Use This Skill For

- Reading the content of a documentation page, blog post, changelog, wiki,
  GitHub page, or any server-rendered site (SSR output parses fine).
- Checking a page's title/headings or pulling the absolute links it contains.
- Reading JSON or plain-text endpoints that a page or API returns — with
  `--backend local`, which returns the bytes unchanged.

Do not use it when:

- The page is a client-side-only app (React/Vue shell) — the fetched HTML has
  no content because MoonBit cannot execute the page's JavaScript. There is no
  CSR-detection heuristic in this tool, so it will happily print what the
  server actually sent: an empty shell. Recognize that situation yourself and
  fall back to the site's JSON API, or say a headless browser would be needed.
  The DeepSeek backend is sometimes better here, and sometimes not: whether
  its extractor runs a browser is not documented, so treat a thin result the
  same way and check.
- You need a screenshot or full DOM after scripts run.

## Running (published package)

From anywhere, run the mooncakes package with moonx (the coordinate is the
module name; no `--` separator before its flags):

```text
moonx tonyfettes/skills-web-fetch <url>
moonx tonyfettes/skills-web-fetch --links <url>
moonx tonyfettes/skills-web-fetch --backend local --raw <url>
moonx tonyfettes/skills-web-fetch --backend deepseek --text 20000 <url>
moonx tonyfettes/skills-web-fetch --help
```

Multiple URLs are printed one after another with a `== url ==` banner; pass
`--stdin` to also read one URL per line from stdin (the sandbox feeds stdin
through, e.g. `stdin=Text(...)`). Exit codes: `0` all pages printed, `1` at
least one page failed (each failure prints one `error: ...` line), `2` usage
error — including `--backend deepseek` with no key.

`moonx` pulls the module from mooncakes.io; the module must be **published**
first (`moon login` + `moon publish` from this directory). While developing
locally, run the same binary from here with:

```text
moon run --target native . -- <url>
moon test                       # unit tests across internal/* packages
moon cram test tests/cram       # offline CLI contract tests
moon build --target wasm        # what moonx will run
```

### Named script (SeekMoon / OpenSeek)

The skill ships a named script at `scripts/fetch.mbtx`, right beside this
`SKILL.md` in the skill's own directory. Which directory that is depends on the
platform and the install: the global library is `~/.openseek/skills`
(`%USERPROFILE%\.openseek\skills` on Windows), and
`$OPENSEEK_GLOBAL_SKILLS_DIR` or a project's `.openseek/skills` can replace it —
so take the path from the skills list the agent was given: this skill's entry
ends in `/SKILL.md`, and the script is `scripts/fetch.mbtx` beside it.

It lets an agent call the CLI without writing an inline `moonx` wrapper: every
argument is forwarded to `moonx tonyfettes/skills-web-fetch`, and that process's
status becomes the script's own (`0` all pages printed, `1` a page failed, `2`
usage error). It needs only `moonx`, so it runs from any workspace.

`mbtx(filename=...)` resolves a relative path from the **agent's workspace
root**, not from the skill directory, and expands neither `~` nor `$VAR`, so
pass that absolute path:

```text
# <skill-dir> is the directory this skill is listed under, e.g.
#   /Users/you/.openseek/skills/tonyfettes-skills-web-fetch       (macOS)
#   /home/you/.openseek/skills/tonyfettes-skills-web-fetch        (Linux)
#   C:\Users\you\.openseek\skills\tonyfettes-skills-web-fetch     (Windows)
mbtx(filename="<skill-dir>/scripts/fetch.mbtx", args=["<url>"])
```

The child process inherits the caller's environment, so `$DEEPSEEK` reaches
the CLI through the script without being passed as an argument.

### Options

| option | meaning |
| --- | --- |
| `--backend <name>` | `auto` (default), `deepseek`, or `local` |
| `--api-key <key>` | DeepSeek API key (default: `$DEEPSEEK`, then `$DEEPSEEK_API_KEY`) |
| `--base-url <url>` | DeepSeek API base (default `https://api.deepseek.com`) |
| `--raw` | print the raw response body instead of extracting text (local backend only: selects it under `auto`, implies nothing else; combining it with `--backend deepseek` is a usage error) |
| `--links` | also list the absolute links the page contains, as `- label: url` |
| `--stdin` | additionally read one URL per line from stdin (blank lines ignored) |
| `--max <bytes>` | cap the local response body size (default 2000000) |
| `--text <chars>` | cap extracted/printed text per page (default 400000) |
| `--ua <string>` | set the User-Agent header of the local fetcher |
| `-h`, `--help` | usage text |

## Backends

`auto` resolves the key the same way every time: `--api-key`, then
`$DEEPSEEK`, then `$DEEPSEEK_API_KEY`; a blank value counts as absent, so an
exported empty variable cannot select the billed backend by accident.

| | DeepSeek Fetch | Local |
| --- | --- | --- |
| needs | an API key | nothing |
| output | DeepSeek's Markdown rendering | the local extractor's text |
| cost | $0.75 per 1,000 successful fetches; failures are free | free |
| limits | 25 QPS per account, plus a per-domain QPS limit (HTTP 429 past either) | none imposed by us |
| privacy | the URL goes to `api.deepseek.com` | the request goes straight to the target host |
| JSON / text bodies | returned Markdown-escaped | returned byte-exact |

DeepSeek's Markdown rendering escapes punctuation (`\.`, `\,`, `\-`), which is
harmless for prose and noisy for JSON and plain text. That is the one case where
the backends differ in practice: pass `--backend local` when you need an API
response or a text file exactly as served, or when the URL must not leave the
machine.

The API is billed per successful request, so this tool never retries on its
own. `408`, `429` and `5xx` are the statuses worth retrying — after a wait, or
with fewer concurrent requests; every other 4xx needs a different request.

## Output Shape

Both backends print the same shape:

```text
Title: Example Domain

# Example Domain

This domain is for use in documentation examples without needing permission. Avoid use in operations.
```

- The `Title:` line and the blank line after it are omitted when the backend
  found no title. The body follows as Markdown (`#`–`######` headings, `- `
  list items), truncated at `--text` chars with a trailing `[...]` marker.
- Locally, extraction starts at the first `<main>` or `<article>`; otherwise
  the whole `<body>` is used, so site chrome (`<nav>`, menus) is usually
  excluded. `<script>`, `<style>`, `<template>`, SVG, and friends are dropped;
  `<pre>` text keeps its formatting. It is a lightweight rendering, not a
  faithful HTML→Markdown conversion.
- Local non-HTML responses (JSON, text/plain, XML, or an HTML-looking body
  without an HTML content type) print their body as-is.
- `--links` works on both: locally the links come from the parsed DOM, on the
  DeepSeek backend from the `[label](url)` pairs in the returned Markdown.
  Relative targets are skipped there, and an empty label falls back to the URL.

## Errors and exit codes

- `0` — every requested page printed.
- `1` — at least one page failed; each failure prints one
  `error: ...` line, the rest are still attempted.
- `2` — usage error (bad option or value, no URL given, `--backend deepseek`
  without a key, `--raw` together with `--backend deepseek`).

Local failures are plain: `error: HTTP 404 Not Found for <url>`, redirect
loops, non-UTF-8 bodies, and network/TLS failures are all reported with the
URL. DeepSeek failures name the API and keep the provider's own message:

```text
error: DeepSeek Fetch HTTP 404 for <url>: could not retrieve usable page content
error: DeepSeek Fetch HTTP 401 for <url>: invalid or missing API key: <provider message>
error: could not reach the DeepSeek Fetch API (<base-url>) for <url>: network or TLS failure
error: URL must contain a host for <url>
error: URL must not contain a username or password for <url>
```

The URL is checked in-process first (at most 8192 characters, `http`/`https`
with a host — a port-only authority such as `https://:8080/x` does not count —
and no embedded credentials or blanks), so a rejected URL costs no request.
The documented DeepSeek statuses are `400` invalid request, `401` bad key,
`402` insufficient balance, `403` blocked by the security policy, `404` no
usable page content, `408` timeout, `413` body too large, `429` rate limited,
`500`/`504` server side.

## Practical guidance

- Keep `--text` small when the page might be long and you only need an
  overview; raise it when you need full prose.
- Use `--links` to find the next hop instead of hand-parsing HTML.
- Use `--raw` only when you need the exact markup; it is local-only.
- Locally, bodies are decoded as UTF-8 only; legacy charsets (e.g. GBK,
  latin-1) come out mojibake — say so rather than pretending the text is
  accurate. The DeepSeek backend decodes and renders server-side, so it may do
  better or worse; if the text looks wrong, try the other backend.
- Redirects are followed locally up to 10 hops (Location header resolution
  included); the DeepSeek backend follows them on its side.
- The local backend is anonymous: no cookies or ambient credentials, and no
  SSRF filtering — do not point it at private/internal URLs or anything that
  requires auth. The DeepSeek backend applies its own security policy and
  returns `403`/`404` instead.
