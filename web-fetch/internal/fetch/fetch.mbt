///|
pub suberror FetchError {
  TooManyRedirects(String)
  HttpStatus(Int, String, String)
  RequestFailed(String, String)
  NotText(String)
}

///|
pub struct Page {
  url : String
  content_type : String
  body : String
}

///|
const MAX_REDIRECTS : Int = 10

///|
const DEFAULT_MAX_BYTES : Int = 2_000_000

///|
fn headers_map(user_agent : String) -> @http.Headers {
  let headers : @http.Headers = Map([])
  headers["User-Agent"] = user_agent
  headers
}

///|
fn content_type_of(resp : @http.Response) -> String {
  match resp.headers.get("content-type") {
    Some(value) => {
      let lower = value.to_lower()
      if lower.find(";") is Some(i) {
        lower[:i].trim().to_owned()
      } else {
        lower.trim().to_owned()
      }
    }
    None => ""
  }
}

///|
/// Fetch `url`, following up to 10 HTTP redirects, and return the final
/// response with its body decoded as UTF-8 (capped at `max_bytes`).
pub async fn fetch_page(
  url : String,
  max_bytes? : Int = DEFAULT_MAX_BYTES,
  user_agent? : String = "tonyfettes/skills-web-fetch/0.1",
) -> Page {
  let headers = headers_map(user_agent)
  let (final_url, resp, data) = redirect_get(url, 0, headers)
  let code = resp.code
  guard code >= 200 && code < 300 else {
    raise FetchError::HttpStatus(code, final_url, resp.reason)
  }
  let text = data.text() catch { _ => raise FetchError::NotText(final_url) }
  let body = if text.length() > max_bytes {
    text[:max_bytes].to_owned()
  } else {
    text
  }
  { url: final_url, content_type: content_type_of(resp), body, }
}

///|
async fn redirect_get(
  url : String,
  hops : Int,
  headers : @http.Headers,
) -> (String, @http.Response, &@io.Data) {
  if hops > MAX_REDIRECTS {
    raise FetchError::TooManyRedirects(url)
  }
  let (resp, data) = @http.get(url, headers~) catch {
    _ => raise FetchError::RequestFailed(url, "network or TLS failure")
  }
  if resp.code >= 300 && resp.code < 400 {
    match resp.headers.get("location") {
      Some(loc) =>
        match @url.absolute_url(url, loc) {
          Some(next) => return redirect_get(next, hops + 1, headers)
          None => ()
        }
      None => ()
    }
  }
  (url, resp, data)
}

///|
/// Decide whether a response body is HTML worth parsing. `content_type` is the
/// lower-cased, parameter-stripped value of the Content-Type header.
pub fn looks_like_html(content_type : String, body : String) -> Bool {
  if content_type.contains("html") {
    return true
  }
  if content_type.contains("json") ||
    content_type.contains("xml") ||
    content_type.contains("text/plain") {
    return false
  }
  let trimmed = body.trim()
  let head = (if trimmed.length() > 512 {
    trimmed[:512].to_owned()
  } else {
    trimmed.to_owned()
  }).to_lower()
  if head.has_prefix("<!doctype html") || head.has_prefix("<html") {
    return true
  }
  content_type.is_empty() &&
  (head.contains("<html") || head.contains("<body") || head.contains("<title"))
}
