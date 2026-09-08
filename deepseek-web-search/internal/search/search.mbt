///|
/// Default endpoint base: DeepSeek's Anthropic-compatible Messages API, `/v1`
/// included (`/messages` is appended). The tool deliberately does not reuse a
/// chat-completions proxy URL: this route is Anthropic-shaped.
pub const DefaultBaseUrl : String = "https://api.deepseek.com/anthropic/v1"

///|
/// Default Anthropic-format model name for the auxiliary search call. The
/// flash tier: the call exists to trigger native search and return result
/// blocks, not to think.
pub const DefaultSearchModel : String = "deepseek-v4-flash"

///|
/// `anthropic-version` header value sent on every request.
pub const AnthropicVersion : String = "2023-06-01"

///|
/// Upper bound on generated tokens for the Messages request. The searching
/// model's prose is discarded (only result blocks survive), so this caps cost,
/// not quality.
pub const DefaultMaxTokens : Int = 4096

///|
/// Maximum native `web_search` server-tool uses per request.
pub const DefaultMaxUses : Int = 5

///|
/// Upper bound on sources returned. Owned by the caller, not the provider.
pub const DefaultMaxResults : Int = 8

///|
/// Wall bound on one whole search call.
pub const DefaultTimeoutMs : Int = 120_000

///|
/// Input cap: a query is a question, not a document.
pub const MaxQueryChars : Int = 2_000

///|
/// One citeable source parsed out of a `web_search_tool_result` block.
/// `snippet` is joined in from a `text` block's citations by URL — the result
/// items themselves typically carry none.
pub struct WebSource {
  url : String
  title : String?
  snippet : String?
  published_at : String?
}

///|
/// Normalized search outcome: sources already deduped and cut to the result
/// cap, plus whether that cut dropped anything.
pub struct SearchOutcome {
  sources : Array[WebSource]
  truncated : Bool
}

///|
/// A search failure with a clean message (no source-location prefix).
pub suberror SearchFailure {
  SearchFailure(String)
}

///|
impl Show for SearchFailure with fn output(
  self : SearchFailure,
  logger : &Logger,
) -> Unit {
  let SearchFailure(message) = self
  logger.write_string(message)
}

///|
/// Collapse `text` to one line and cap it to `limit` characters (appending `…`
/// when cut). Iterates by character so a cap never splits a surrogate pair;
/// line breaks and tabs become spaces, other C0 controls and DEL are dropped.
pub fn cap_line(text : String, limit : Int) -> String {
  let sanitized = StringBuilder()
  for ch in text {
    if ch is ('\n' | '\r' | '\t') {
      sanitized.write_char(' ')
    } else if ch.to_int() < 0x20 || ch.to_int() == 0x7F {
      continue
    } else {
      sanitized.write_char(ch)
    }
  }
  let one = sanitized.to_string().trim()
  if one.length() <= limit {
    "\{one}"
  } else {
    "\{String::from_iter(one.iter().take(limit))}…"
  }
}

///|
/// Escape the square brackets markdown link labels delimit, so a
/// provider-controlled title cannot break the `[label](url)` shape.
pub fn markdown_label(text : String) -> String {
  text.replace_all(old="[", new="\\[").replace_all(old="]", new="\\]")
}

///|
/// One search: POST the Messages request with the native server tool, bounded
/// by `timeout_ms`, and map the response to a normalized outcome.
pub async fn perform_search(
  api_key~ : String,
  base_url? : String = DefaultBaseUrl,
  model? : String = DefaultSearchModel,
  max_results? : Int = DefaultMaxResults,
  max_uses? : Int = DefaultMaxUses,
  max_tokens? : Int = DefaultMaxTokens,
  timeout_ms? : Int = DefaultTimeoutMs,
  query : String,
) -> SearchOutcome {
  let body : Json = {
    "model": model.to_json(),
    "max_tokens": max_tokens.to_json(),
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Perform a web search for the query: \{query}".to_json(),
          },
        ],
      },
    ],
    "tools": [
      {
        "type": "web_search_20250305",
        "name": "web_search",
        "max_uses": max_uses.to_json(),
      },
    ],
  }
  // Official DeepSeek expects `x-api-key`; an Anthropic-compatible proxy may
  // expect `Authorization: Bearer` — send both so either resolves.
  let attempt = () => {
    @http.post("\{base_url}/messages", body, headers={
      "Content-Type": "application/json",
      "X-Api-Key": api_key,
      "Authorization": "Bearer \{api_key}",
      "Anthropic-Version": AnthropicVersion,
    })
  }
  guard @async.with_timeout_opt(timeout_ms, attempt) is Some((resp, data)) else {
    raise SearchFailure("web search timed out after \{timeout_ms}ms")
  }
  let text = data.text()
  guard resp.code >= 200 && resp.code < 300 else {
    raise SearchFailure(
      "DeepSeek search API error \{resp.code}: \{error_detail(text)}",
    )
  }
  let payload = @json.parse(text) catch {
    _ => raise SearchFailure("DeepSeek search response is not JSON")
  }
  parse_search_response(payload, max_results~)
}

///|
/// Best-effort human message from an error body: the Anthropic-style
/// `error.message` (or flat `error`/`message` string) when present, else the
/// raw body capped to one short line — gateways return HTML pages that must
/// not flood the output.
pub fn error_detail(text : String) -> String {
  let parsed = @json.parse(text) catch { _ => return cap_line(text, 200) }
  match parsed {
    { "error": { "message": String(message), .. }, .. } => message
    { "error": String(message), .. } => message
    { "message": String(message), .. } => message
    _ => cap_line(text, 200)
  }
}

///|
/// Map a DeepSeek Anthropic Messages response to a normalized outcome. Walks
/// `web_search_tool_result` blocks for citeable `web_search_result` items,
/// joins each to its citation excerpt as `snippet` (the excerpt lives in a
/// separate `text` block's `citations[]`, keyed by URL, first occurrence
/// wins), dedupes by URL (a `max_uses > 1` request can surface the same URL
/// across searches), and cuts to `max_results`. Raises when native search
/// produced no result block at all — that is a provider misfire, not an empty
/// result.
pub fn parse_search_response(
  payload : Json,
  max_results~ : Int,
) -> SearchOutcome raise {
  guard payload is { "content": Array(blocks), .. } else {
    raise SearchFailure("DeepSeek search response has no content blocks")
  }
  // url → cited_text from every text block's citations; the snippet source.
  let snippets : Map[String, String] = Map([])
  for block in blocks {
    guard block is { "type": "text", .. } else { continue }
    guard block is { "citations": Array(citations), .. } else { continue }
    for citation in citations {
      guard citation is { "url": String(url), "cited_text": String(cited), .. } &&
        url != "" &&
        cited != "" else {
        continue
      }
      if !snippets.contains(url) {
        snippets[url] = cited
      }
    }
  }
  let mut found_result_block = false
  let sources : Array[WebSource] = []
  let error_codes : Array[String] = []
  let mut dropped = false
  for block in blocks {
    guard block is { "type": "web_search_tool_result", .. } else { continue }
    found_result_block = true
    // A server-side search failure arrives as an OBJECT content
    // (`{"type":"web_search_tool_result_error","error_code":...}`) instead of
    // the item array. Collect the code rather than skipping, so an all-error
    // response raises below instead of rendering as a clean "No results
    // found." the caller would trust.
    if block is { "content": { .. } as error_content, .. } {
      let code = match error_content {
        { "error_code": String(code), .. } => code
        _ => "unknown error"
      }
      error_codes.push(code)
      continue
    }
    guard block is { "content": Array(items), .. } else { continue }
    for item in items {
      guard item is { "type": "web_search_result", "url": String(url), .. } &&
        url != "" else {
        continue
      }
      if sources.iter().any(source => source.url == url) {
        continue
      }
      if sources.length() >= max_results {
        dropped = true
        continue
      }
      let title = match item {
        { "title": String(title), .. } if title != "" => Some(title)
        _ => None
      }
      let published_at = match item {
        { "page_age": String(age), .. } if age != "" => Some(age)
        _ => None
      }
      sources.push({ url, title, snippet: snippets.get(url), published_at, })
    }
  }
  guard found_result_block else {
    raise SearchFailure(
      "DeepSeek returned no web_search_tool_result blocks; the request may not have triggered native web search",
    )
  }
  // Partial failures (one errored search among successful ones) still return
  // the gathered sources; only an all-error response is an error.
  if sources.is_empty() && !error_codes.is_empty() {
    raise SearchFailure(
      "DeepSeek native web search failed server-side: \{error_codes.join(", ")}",
    )
  }
  { sources, truncated: dropped, }
}

///|
/// Display label for a title-less source: the URL's hostname (scheme,
/// userinfo, port, and path stripped), or the raw URL when it does not parse
/// as one — never let a malformed provider URL throw out of pure formatting.
pub fn host_label(url : String) -> String {
  guard url =~ (re"^[A-Za-z][A-Za-z0-9+.\-]*://", after~) else { return url }
  let mut authority = after
  // Path/query/fragment start at the first delimiter; userinfo ends at the
  // first `@` (a host cannot contain one); the port starts at the first `:`
  // of what remains. Each step narrows the view, so the order matters.
  if authority =~ (re"[/?#]", before~) {
    authority = before
  }
  if authority =~ (re"@", after~) {
    authority = after
  }
  // A bracketed IPv6 literal is the whole host; the port (if any) follows the
  // closing bracket, so the first-`:` port strip below must not see it.
  if authority =~ (re"^\[", after~) {
    guard after =~ (re"\]", before~) else { return url }
    return "[\{before}]"
  }
  if authority =~ (re":", before~) {
    authority = before
  }
  if authority.is_empty() {
    url
  } else {
    authority.to_owned()
  }
}

///|
/// Format a search outcome as one text block: a markdown source list with
/// snippet and date metadata (or `No results found.`), a refine-the-query
/// note when truncated, and a standing cite-your-sources instruction.
pub fn format_output(outcome : SearchOutcome) -> String {
  let parts : Array[String] = []
  if outcome.sources.length() > 0 {
    let lines = [
      for source in outcome.sources => {
        // Provider-controlled text: collapse to one line and cap each field
        // (only the source COUNT is bounded upstream), and escape the square
        // brackets markdown link labels delimit — otherwise a title or
        // excerpt can break the `- [label](url) — meta` line shape or flood
        // the transcript.
        let label = markdown_label(
          match source.title {
            Some(title) => cap_line(title, 120)
            None => host_label(source.url)
          },
        )
        let meta : Array[String] = []
        if source.snippet is Some(snippet) {
          meta.push(cap_line(snippet, 300))
        }
        if source.published_at is Some(published) {
          let capped = cap_line(published, 40)
          meta.push("(\{capped})")
        }
        let suffix = if meta.length() > 0 {
          " — \{meta.join(" ")}"
        } else {
          ""
        }
        "- [\{label}](\{source.url})\{suffix}"
      }
    ]
    parts.push("Sources:\n\{lines.join("\n")}")
  } else {
    parts.push("No results found.")
  }
  if outcome.truncated {
    parts.push(
      "(Showing the first \{outcome.sources.length()} sources. Refine the query for more.)",
    )
  }
  parts.push("Cite the relevant URLs above as markdown links in your answer.")
  parts.join("\n\n")
}
