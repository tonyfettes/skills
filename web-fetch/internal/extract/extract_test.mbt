///|
test "article extraction prefers main/article and keeps pre" {
  let html =
    #|<html><head><title>Doc Title</title></head><body><nav><a href="/menu">Menu</a></nav><article><h1>Hello World</h1><p>Some <b>bold</b> text and a <a href="https://example.com/x">link here</a>.</p><ul><li>first</li><li>second</li></ul><pre>a  b
    #|c</pre></article></body></html>
  let article = extract_article(html, "https://example.com/dir/page")
  assert_eq(article.title, "Doc Title")
  assert_true(article.text.contains("# Hello World"))
  assert_true(article.text.contains("Some bold text and a link here."))
  assert_true(article.text.contains("- first"))
  assert_true(article.text.contains("- second"))
  assert_true(article.text.contains("a  b\nc"))
  // nav chrome is outside <article>, so excluded from text and links
  assert_true(!article.text.contains("Menu"))
  assert_eq(article.links, [("link here", "https://example.com/x")])
}

///|
test "whole-body fallback skips scripts and resolves relative links" {
  let html =
    #|<html><head><title>X</title></head><body><h1>T</h1><p>para one</p><script>var x = 1;</script><style>.y{}</style><p>para two <a href="../up">rel</a></p></body></html>
  let article = extract_article(html, "https://example.com/dir/deep/page.html")
  assert_eq(article.title, "X")
  assert_true(article.text.contains("para one"))
  assert_true(article.text.contains("para two"))
  assert_true(!article.text.contains("var x"))
  assert_true(!article.text.contains(".y{}"))
  assert_eq(article.links, [("rel", "https://example.com/dir/up")])
}

///|
test "title falls back to first h1" {
  let html =
    #|<html><body><h1>Fallback Title</h1><p>Only para</p></body></html>
  let article = extract_article(html, "https://example.com/")
  assert_eq(article.title, "Fallback Title")
  assert_true(article.text.contains("Only para"))
}
