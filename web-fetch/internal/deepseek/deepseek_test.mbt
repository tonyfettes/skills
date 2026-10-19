///|
fn parse_or_none(text : String) -> @deepseek.Page? {
  Some(@deepseek.parse_page(text)) catch {
    _ => None
  }
}

///|
test "validate_url accepts plain http and https urls" {
  assert_eq(@deepseek.validate_url("https://example.com/"), None)
  assert_eq(@deepseek.validate_url("http://example.com/a?b=c#d"), None)
  assert_eq(@deepseek.validate_url("HTTPS://EXAMPLE.COM/"), None)
}

///|
test "validate_url rejects what the api rejects" {
  assert_true(@deepseek.validate_url("ftp://example.com/") is Some(_))
  assert_true(@deepseek.validate_url("example.com") is Some(_))
  assert_true(@deepseek.validate_url("https://") is Some(_))
  assert_true(@deepseek.validate_url("https:///path") is Some(_))
  assert_true(@deepseek.validate_url("https://?q=1") is Some(_))
  assert_true(@deepseek.validate_url("https://user:pw@example.com/") is Some(_))
}

///|
test "validate_url enforces the documented length cap" {
  let long = "https://example.com/" + Array::make(9000, "a").join("")
  assert_eq(long.length(), 9020)
  assert_true(@deepseek.validate_url(long) is Some(_))
  let longest = "https://example.com/" + Array::make(8192 - 20, "a").join("")
  assert_eq(longest.length(), 8192)
  assert_true(@deepseek.validate_url(longest) is None)
}

///|
test "parse_page reads the documented response" {
  let page = @deepseek.parse_page(
    "{\"title\":\"Example\",\"content\":\"# Hi\"}",
  )
  assert_eq(page.title, "Example")
  assert_eq(page.content, "# Hi")
}

///|
test "parse_page tolerates a missing title" {
  let page = @deepseek.parse_page("{\"content\":\"# Hi\"}")
  assert_eq(page.title, "")
  assert_eq(page.content, "# Hi")
}

///|
test "parse_page rejects a body that is not the documented object" {
  assert_true(parse_or_none("{\"title\":\"x\"}") is None)
  assert_true(parse_or_none("not json") is None)
  assert_true(parse_or_none("[]") is None)
}

///|
test "markdown_links keeps absolute targets and drops the rest" {
  let text = "See [MoonBit](https://www.moonbitlang.com/) and [docs](/docs) and [mail](mailto:a@b.c)."
  assert_eq(@deepseek.markdown_links(text), [
    ("MoonBit", "https://www.moonbitlang.com/"),
  ])
}

///|
test "markdown_links skips images and de-duplicates by url" {
  let text =
    #|![logo](https://img.example/logo.png)
    #|[first](https://a.example/one) then [again](https://a.example/one) and [second](http://b.example/two).
  assert_eq(@deepseek.markdown_links(text), [
    ("first", "https://a.example/one"),
    ("second", "http://b.example/two"),
  ])
}

///|
test "markdown_links unwraps angle brackets and empty labels" {
  // A label of blanks falls back to the URL, and an angle-bracketed target is
  // unwrapped, the way Markdown writers spell a bare link.
  assert_eq(
    @deepseek.markdown_links(
      "[ ]( <https://a.example/x> ) and [](https://b.example/y)",
    ),
    [
      ("https://a.example/x", "https://a.example/x"),
      ("https://b.example/y", "https://b.example/y"),
    ],
  )
  assert_eq(@deepseek.markdown_links("[](https://b.example/y)"), [
    ("https://b.example/y", "https://b.example/y"),
  ])
}

///|
test "markdown_links stops at a newline inside a link" {
  assert_eq(@deepseek.markdown_links("[broken](https://a.example/\nnext)"), [])
}

///|
test "markdown_links honours the limit" {
  let text = "[a](https://a.example/1) [b](https://a.example/2) [c](https://a.example/3)"
  assert_eq(@deepseek.markdown_links(text, limit=2).length(), 2)
  assert_eq(@deepseek.markdown_links(text, limit=0).length(), 0)
}

///|
test "validate_url requires a host, not just an authority" {
  // A port-only authority, or a blank inside the host, must not reach the API:
  // each of these would otherwise be a billed request for a URL the docs reject.
  assert_true(@deepseek.validate_url("https://:8080/x") is Some(_))
  assert_true(@deepseek.validate_url("https://exa mple.com/x") is Some(_))
  assert_true(@deepseek.validate_url("https://user@/x") is Some(_))
  assert_true(@deepseek.validate_url("https://[]/x") is Some(_))
  assert_true(@deepseek.validate_url("https://example.com:8080/x") is None)
  assert_true(@deepseek.validate_url("https://[::1]:8080/x") is None)
}

///|
test "endpoint_for appends the documented path" {
  assert_eq(
    @deepseek.endpoint_for("https://api.deepseek.com"),
    "https://api.deepseek.com/v1/tools/fetch",
  )
  assert_eq(
    @deepseek.endpoint_for("https://api.deepseek.com/"),
    "https://api.deepseek.com/v1/tools/fetch",
  )
  assert_eq(
    @deepseek.endpoint_for("https://proxy.example/ds/"),
    "https://proxy.example/ds/v1/tools/fetch",
  )
}
