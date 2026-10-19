///|
/// The DeepSeek Fetch backend: `POST {base}/v1/tools/fetch` with a bearer API
/// key returns `{ "title": String, "content": String }`, where `content` is
/// the page rendered as Markdown by DeepSeek's own extractor.
///
/// Reference: https://api-docs.deepseek.com/api/fetch/
///
/// The request is billed per successful call (HTTP 200 with page content), not
/// per byte or per token, so this module never retries on its own: a caller
/// that sees a retryable status decides whether the extra call is worth it.

///|
/// Errors raised by the DeepSeek Fetch backend.
pub suberror FetchError {
  /// The URL breaks the documented request rules, so no request was sent; the
  /// payload is the user-facing reason.
  InvalidUrl(String)
  /// The API answered with a non-2xx status, or could not be reached at all
  /// (`status` is `0` then). The second field is a short reason, with the
  /// provider's own message appended when it sent one.
  HttpStatus(Int32, String)
  /// The response body was not the documented `{ "title", "content" }` object.
  Malformed(String)
}

///|
/// One page as DeepSeek Fetch returns it: the page title (empty when DeepSeek
/// could not find one) and the content as Markdown text.
pub struct Page {
  title : String
  content : String
}

///|
/// The DeepSeek API base; `/v1/tools/fetch` is appended to it.
pub const DEFAULT_BASE_URL : String = "https://api.deepseek.com"

///|
/// The documented maximum length of the request `url` field.
pub const MAX_URL_LENGTH : Int32 = 8192

///|
/// The documented request rules for `url`: at most 8192 characters, an
/// `http`/`https` URL with a host, and no username or password. Returns the
/// user-facing reason when the URL is not acceptable, so the CLI can report it
/// without spending a request.
pub fn validate_url(url : String) -> String? {
  if url.length() > MAX_URL_LENGTH {
    return Some("URL is longer than \{MAX_URL_LENGTH} characters")
  }
  let view : StringView = url[:]
  let lower = url.to_lower()
  let rest = if lower.has_prefix("https://") {
    view[8:]
  } else if lower.has_prefix("http://") {
    view[7:]
  } else {
    return Some("URL must be an http:// or https:// URL")
  }
  let authority = rest[:authority_end(rest)]
  if authority.contains("@") {
    return Some("URL must not contain a username or password")
  }
  if has_blank_or_control(authority) {
    return Some("URL must not contain spaces or control characters")
  }
  if host_of(authority).is_empty() {
    return Some("URL must contain a host")
  }
  None
}

///|
/// The host of an authority, ignoring an optional port: `example.com:8080`
/// yields `example.com`, and a bracketed IPv6 literal yields its inner address.
/// `:8080` on its own yields nothing, which is what makes a port-only
/// authority fail the host check instead of slipping through to a request.
fn host_of(authority : StringView) -> StringView {
  if authority.has_prefix("[") {
    match authority.find("]") {
      Some(close) => authority[1:close]
      None => authority[1:]
    }
  } else {
    match authority.find(":") {
      Some(colon) => authority[:colon]
      None => authority
    }
  }
}

///|
fn has_blank_or_control(authority : StringView) -> Bool {
  for c in authority {
    if c <= ' ' || c == '\u{7F}' {
      return true
    }
  }
  false
}

///|
/// Fetch one page through DeepSeek's Fetch API.
///
/// `api_key` is sent as `Authorization: Bearer`; `base_url` defaults to the
/// public DeepSeek API and is overridable for a compatible proxy.
pub async fn fetch_page(
  url : String,
  api_key : String,
  base_url~ : String = DEFAULT_BASE_URL,
  user_agent~ : String = "tonyfettes/skills-web-fetch/0.2",
) -> Page {
  match validate_url(url) {
    Some(reason) => raise FetchError::InvalidUrl(reason)
    None => ()
  }
  let endpoint = endpoint_for(base_url)
  let headers : @http.Headers = Map([])
  headers["Authorization"] = "Bearer \{api_key}"
  headers["Content-Type"] = "application/json"
  headers["Accept"] = "application/json"
  headers["User-Agent"] = user_agent
  let body : Json = { "url": url }
  let (resp, data) = @http.post(endpoint, body.stringify(), headers~) catch {
    _ => raise FetchError::HttpStatus(0, "network or TLS failure")
  }
  // Status first: a gateway can answer a failure with a body that is not even
  // UTF-8, and losing the status to a decode error would hide the real cause.
  let decoded = Some(data.text()) catch { _ => None }
  if resp.code < 200 || resp.code >= 300 {
    let detail = match decoded {
      Some(body) => error_reason(resp.code, body)
      None => status_reason(resp.code)
    }
    raise FetchError::HttpStatus(resp.code, detail)
  }
  let text = match decoded {
    Some(body) => body
    None => raise FetchError::Malformed("the response body is not UTF-8 text")
  }
  parse_page(text)
}

///|
/// The Fetch endpoint for a base URL: `/v1/tools/fetch` is appended after any
/// trailing slashes are removed, so `https://api.deepseek.com`, the same with a
/// trailing slash, and a proxied base with a path all name one endpoint.
pub fn endpoint_for(base_url : String) -> String {
  "\{trim_end_slash(base_url)}/v1/tools/fetch"
}

///|
/// Parse a Fetch API response body into a page. Both response fields are
/// documented as required strings; a missing `title` is tolerated as empty,
/// a missing `content` is not, because an empty page is never useful.
pub fn parse_page(text : String) -> Page raise FetchError {
  let json = @json.parse(text) catch {
    _ => raise FetchError::Malformed("the response body is not JSON")
  }
  let title = match json {
    { "title": String(title), .. } => title
    _ => ""
  }
  match json {
    { "content": String(content), .. } => { title, content, }
    _ => raise FetchError::Malformed("the response has no content field")
  }
}

///|
/// Collect the `[label](url)` links of a Markdown document: absolute `http(s)`
/// targets only, de-duplicated by URL, in document order.
pub fn markdown_links(
  markdown : String,
  limit~ : Int32 = 200,
) -> Array[(String, String)] {
  let links : Array[(String, String)] = []
  let seen : Map[String, Unit] = Map([])
  let view : StringView = markdown[:]
  let mut from = 0
  while links.length() < limit {
    guard index_of(view, "](", from) is Some(close) else { break }
    let mut next = close + 2
    if find_label(view, close, from) is Some(open) &&
      target_after(view, close + 2) is Some((target, end)) {
      let url = strip_angle_brackets(target)
      if is_absolute_url(url) && !seen.contains(url.to_owned()) {
        seen[url.to_owned()] = ()
        let label = view[open + 1:close].trim().to_owned()
        let label = if label.is_empty() { url.to_owned() } else { label }
        links.push((label, url.to_owned()))
      }
      next = end
    }
    from = next
  }
  links
}

///|
fn authority_end(rest : StringView) -> Int32 {
  let mut i = 0
  while i < rest.length() {
    let c = rest[i]
    if c == '/' || c == '?' || c == '#' {
      break
    }
    i += 1
  }
  i
}

///|
fn trim_end_slash(base : String) -> String {
  let mut end = base.length()
  while end > 0 && base[end - 1] == '/' {
    end -= 1
  }
  base[:end].to_owned()
}

///|
fn status_reason(code : Int32) -> String {
  match code {
    0 => "network or TLS failure"
    400 => "invalid request"
    401 => "invalid or missing API key"
    402 => "insufficient balance"
    403 => "rejected by the security policy"
    404 => "could not retrieve usable page content"
    408 => "request timed out"
    413 => "request body too large"
    429 => "rate limited"
    500 => "server error"
    504 => "upstream timeout"
    _ => "unexpected status"
  }
}

///|
/// A short reason for a non-2xx status, with the provider's own `error.message`
/// appended when the body carries one (the docs promise an OpenAI-compatible
/// error object, but gateways can answer with plain text or HTML).
fn error_reason(code : Int32, body : String) -> String {
  let base = status_reason(code)
  let parsed = @json.parse(body) catch { _ => return base }
  match parsed {
    { "error": { "message": String(message), .. }, .. } =>
      if message.is_empty() {
        base
      } else {
        "\{base}: \{message}"
      }
    _ => base
  }
}

///|
fn index_of(view : StringView, needle : StringView, start : Int32) -> Int32? {
  let n = needle.length()
  let mut i = start
  while i + n <= view.length() {
    if view[i:i + n].equal(needle) {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// The `[` that opens the label ending at `close`, when the label is on one
/// line and is not an image (`![alt](url)`).
fn find_label(view : StringView, close : Int32, from : Int32) -> Int32? {
  let mut i = close - 1
  while i >= from {
    let c = view[i]
    if c == '[' {
      if i > 0 && view[i - 1] == '!' {
        return None
      }
      return Some(i)
    }
    if c == ']' || c == ')' || c == '\n' || c == '\r' {
      return None
    }
    i -= 1
  }
  None
}

///|
/// The link target starting at `start` and the index just past its closing
/// `)`. Markdown forbids an unescaped `)` inside a bare target, so the first
/// one ends it.
fn target_after(view : StringView, start : Int32) -> (StringView, Int32)? {
  let mut i = start
  while i < view.length() {
    let c = view[i]
    if c == ')' {
      return Some((view[start:i].trim(), i + 1))
    }
    if c == '\n' || c == '\r' {
      return None
    }
    i += 1
  }
  None
}

///|
fn strip_angle_brackets(target : StringView) -> StringView {
  if target.length() >= 2 &&
    target[0] == '<' &&
    target[target.length() - 1] == '>' {
    target[1:target.length() - 1]
  } else {
    target
  }
}

///|
fn is_absolute_url(url : StringView) -> Bool {
  let lower = url.to_owned().to_lower()
  lower.has_prefix("http://") || lower.has_prefix("https://")
}
