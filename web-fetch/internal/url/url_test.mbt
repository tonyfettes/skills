///|
test "absolute url resolution" {
  assert_eq(
    absolute_url("https://example.com/a/b/c", "../d"),
    Some("https://example.com/a/d"),
  )
  assert_eq(
    absolute_url("https://example.com/a/b/c?x=1", "e"),
    Some("https://example.com/a/b/e"),
  )
  assert_eq(
    absolute_url("https://example.com/dir/page", "/root"),
    Some("https://example.com/root"),
  )
  assert_eq(
    absolute_url("https://example.com/x", "//cdn.example.com/y"),
    Some("https://cdn.example.com/y"),
  )
  assert_eq(
    absolute_url("https://example.com/x", "http://other.org/z"),
    Some("http://other.org/z"),
  )
  assert_eq(
    absolute_url("https://example.com/a/b/", "c?q=1"),
    Some("https://example.com/a/b/c?q=1"),
  )
  assert_eq(
    absolute_url("https://example.com", "page"),
    Some("https://example.com/page"),
  )
  assert_eq(absolute_url("https://example.com/x", "mailto:a@b.c"), None)
  assert_eq(absolute_url("https://example.com/x", "ftp://files/x"), None)
  assert_eq(absolute_url("https://example.com/x", "#frag"), None)
  assert_eq(absolute_url("https://example.com/x", ""), None)
}
