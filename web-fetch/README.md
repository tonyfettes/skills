# tonyfettes/skills-web-fetch

A tiny "web fetch" CLI written in pure MoonBit: fetch an `http(s)://` URL and
print what an agent actually wants to read — a `Title:` line, then the page as
Markdown.

Two backends produce that shape:

- **DeepSeek Fetch** — `POST https://api.deepseek.com/v1/tools/fetch` returns
  the page already rendered as Markdown (`{ "title", "content" }`). Needs an
  API key and is billed per successful request.
- **Local** — `moonbitlang/async` HTTP plus the WHATWG `moonbit-community/html`
  parser: redirects (up to 10) are followed, relative links are resolved, HTML
  is reduced to title and main text, and non-HTML bodies print raw.

`--backend auto` (default) uses DeepSeek Fetch when a key resolves and the
local fetcher otherwise; `--backend deepseek` and `--backend local` force one.

It powers a SeekMoon-style "web fetch" skill; the module is a single top-level
executable package (root `moon.pkg`) with the logic split into module-internal
packages:

```text
internal/deepseek/  DeepSeek Fetch API client, error mapping, Markdown links
internal/fetch/     local HTTP(S) fetch, redirects, content-type sniffing
internal/extract/   HTML5 → title / readable text / absolute links
internal/url/       relative URL resolution (shared)
```

Static and server-side-rendered pages work out of the box. Client-side-only
apps (React/Vue shells whose HTML contains no content) are out of scope — no
JavaScript engine or headless browser is involved. If content is missing, the
page is a shell; the DeepSeek backend is worth one try there, but it is not a
documented browser fallback either.

## Running

Once published on mooncakes.io:

```text
moonx tonyfettes/skills-web-fetch https://example.com/
moonx tonyfettes/skills-web-fetch --links https://example.com/
moonx tonyfettes/skills-web-fetch --backend local --raw https://example.com/
moonx tonyfettes/skills-web-fetch --backend deepseek https://example.com/
moonx tonyfettes/skills-web-fetch --help
```

Options: `--backend <auto|deepseek|local>`, `--api-key <key>` (default:
`$DEEPSEEK`, then `$DEEPSEEK_API_KEY`), `--base-url <url>` (default
`https://api.deepseek.com`), `--raw` (print the body verbatim; local only — it
selects the local backend under `auto`, and is a usage error next to
`--backend deepseek`), `--links` (also list absolute links as `- label: url`),
`--stdin` (read one URL per line from stdin), `--max <bytes>` (local body size
cap, default 2_000_000), `--text <chars>` (output cap per page, default
400_000), `--ua <string>` (local User-Agent), `-h/--help`.

Exit codes: `0` everything printed; `1` at least one page failed (each failure
prints one `error: ...` line); `2` usage error, including `--backend deepseek`
with no key and `--raw` together with `--backend deepseek`.

## Backends

| | DeepSeek Fetch | Local |
| --- | --- | --- |
| needs | an API key | nothing |
| cost | $0.75 per 1,000 successful fetches (failures free) | free |
| limits | 25 QPS per account plus a per-domain limit | none imposed by us |
| privacy | the URL is sent to `api.deepseek.com` | the request goes to the target host |
| JSON / text bodies | Markdown-escaped | byte-exact |

DeepSeek's renderer escapes punctuation (`\.`, `\,`), so prose reads fine but
JSON comes back noisy. Use `--backend local` when you need an API response or a
text file exactly as served, or when the URL must not go to a third party.

The API bills per successful request, so the tool never retries by itself:
`408`, `429` and `5xx` are worth retrying after a wait; other 4xx need a
different request. Reference: <https://api-docs.deepseek.com/api/fetch/>.

## Named script (SeekMoon / OpenSeek)

The skill ships `scripts/fetch.mbtx` right beside this README, in the skill's
own directory. Which directory that is depends on the platform and the install:
the global library is `~/.openseek/skills` (`%USERPROFILE%\.openseek\skills` on
Windows), and `$OPENSEEK_GLOBAL_SKILLS_DIR` or a project's `.openseek/skills`
can replace it — so take the path from the skills list the agent was given: the
entry ends in `/SKILL.md`, and the script is beside it.

An agent can call it instead of writing an inline `moonx` wrapper; it forwards
every argument, and the CLI's exit status, unchanged (`0` all pages printed,
`1` a page failed, `2` usage error).

`mbtx(filename=...)` resolves a relative path from the **agent's workspace
root**, not from the skill directory, and expands neither `~` nor `$VAR`, so
pass the script's absolute path:

```text
mbtx(filename="<skill-dir>/scripts/fetch.mbtx", args=["https://example.com/"])
```

## Local development

```text
moon test                 # unit tests across the internal packages
moon cram test tests/cram # offline CLI contract tests (no network, no key)
moon run --target native . -- https://example.com/
moon build --target wasm  # the artifact moonx runs
```

The live fixtures (`tests/live`) need network; they pin `--backend local` so
they do not spend DeepSeek requests. To exercise the paid backend by hand:

```text
DEEPSEEK=... moon run --target native . -- --backend deepseek https://example.com/
```

## Notes

- Local bodies are decoded as UTF-8 only; legacy charsets (GBK, latin-1 …) come
  out mojibake. The DeepSeek backend decodes server-side.
- The local fetcher sends no cookies or ambient credentials and performs no
  SSRF filtering — do not point it at private/internal URLs.
- CLI argument parsing tolerates runners that pass `argv[0]` (native `moon
  run`) and those that do not (`moonx`).
