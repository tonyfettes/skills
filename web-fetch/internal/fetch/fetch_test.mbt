///|
test "html sniffing" {
  assert_true(looks_like_html("text/html; charset=utf-8", ""))
  assert_true(looks_like_html("", "<!DOCTYPE html><html></html>"))
  assert_true(!looks_like_html("application/json", "{\"a\": 1}"))
  assert_true(!looks_like_html("text/plain", "<html>not really</html>"))
}
