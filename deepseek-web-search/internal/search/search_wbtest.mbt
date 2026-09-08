///|
test "parse_search_response joins citations, dedupes, and formats" {
  let outcome = parse_search_response(sample_response(), max_results=8)
  assert_eq(outcome.sources.length(), 2)
  assert_false(outcome.truncated)
  let rendered = format_output(outcome)
  assert_eq(
    rendered,
    (
      #|Sources:
      #|- [Example A](https://example.com/a) — MoonBit is a fast language. (January 5, 2026)
      #|- [example.org](https://example.org/b)
      #|
      #|Cite the relevant URLs above as markdown links in your answer.
    ),
  )
}

///|
test "parse_search_response cuts to max_results and flags the cut" {
  let outcome = parse_search_response(sample_response(), max_results=1)
  assert_eq(outcome.sources.length(), 1)
  assert_true(outcome.truncated)
  let rendered = format_output(outcome)
  assert_true(
    rendered.contains(
      "(Showing the first 1 sources. Refine the query for more.)",
    ),
  )
}

///|
test "parse_search_response treats a missing result block as a provider error" {
  let _ = parse_search_response(
    { "content": [{ "type": "text", "text": "just prose" }] },
    max_results=8,
  ) catch {
    error => {
      assert_true("\{error}".contains("no web_search_tool_result blocks"))
      return
    }
  }
  fail("expected the parse to raise")
}

///|
test "format_output renders the empty outcome as no results" {
  let rendered = format_output({ sources: [], truncated: false, })
  assert_true(rendered.contains("No results found."))
}

///|
test "parse_search_response raises on an all-error result block" {
  let _ = parse_search_response(
    {
      "content": [
        {
          "type": "web_search_tool_result",
          "content": {
            "type": "web_search_tool_result_error",
            "error_code": "max_uses_exceeded",
          },
        },
      ],
    },
    max_results=8,
  ) catch {
    error => {
      assert_true("\{error}".contains("failed server-side: max_uses_exceeded"))
      return
    }
  }
  fail("expected the error block to raise")
}

///|
test "parse_search_response keeps sources from a partially errored response" {
  let outcome = parse_search_response(
    {
      "content": [
        {
          "type": "web_search_tool_result",
          "content": {
            "type": "web_search_tool_result_error",
            "error_code": "too_many_requests",
          },
        },
        {
          "type": "web_search_tool_result",
          "content": [
            {
              "type": "web_search_result",
              "url": "https://example.com/a",
              "title": "Example A",
            },
          ],
        },
      ],
    },
    max_results=8,
  )
  assert_eq(outcome.sources.length(), 1)
  assert_false(outcome.truncated)
}

///|
test "error_detail extracts the provider message and caps raw bodies" {
  assert_eq(
    error_detail("{\"error\":{\"type\":\"auth\",\"message\":\"invalid key\"}}"),
    "invalid key",
  )
  assert_eq(error_detail("{\"error\":\"flat message\"}"), "flat message")
  let capped = error_detail("<html>" + "x".repeat(400) + "</html>")
  assert_true(capped.length() <= 201)
  assert_true(capped.has_suffix("…"))
}

///|
test "host_label extracts the hostname and falls back to the raw string" {
  assert_eq(host_label("https://example.com/a/b?q=1"), "example.com")
  assert_eq(host_label("https://user:pw@example.org:8443/x"), "example.org")
  assert_eq(host_label("http://localhost:8080"), "localhost")
  assert_eq(host_label("not a url"), "not a url")
  assert_eq(host_label("https:///path"), "https:///path")
}

///|
test "host_label keeps bracketed IPv6 hosts whole" {
  assert_eq(host_label("https://[::1]:8080/x"), "[::1]")
  assert_eq(host_label("http://[2001:db8::1]/path"), "[2001:db8::1]")
  assert_eq(host_label("https://[broken"), "https://[broken")
}

///|
test "format_output collapses, caps, and escapes provider text" {
  let outcome : SearchOutcome = {
    sources: [
      {
        url: "https://example.com/a",
        title: Some("Release [v2.0] notes"),
        snippet: Some("line one\nline two"),
        published_at: None,
      },
    ],
    truncated: false,
  }
  let rendered = format_output(outcome)
  assert_true(
    rendered.contains(
      "- [Release \\[v2.0\\] notes](https://example.com/a) — line one line two",
    ),
  )
}

///|
test "format_output caps runaway snippets" {
  let outcome : SearchOutcome = {
    sources: [
      {
        url: "https://example.com/a",
        title: None,
        snippet: Some("s".repeat(1000)),
        published_at: None,
      },
    ],
    truncated: false,
  }
  let rendered = format_output(outcome)
  // The 300-char field cap (plus ellipsis) keeps the whole render bounded.
  assert_true(rendered.length() < 500)
  assert_true(rendered.contains("…"))
}

///|
/// A canned Anthropic-style Messages response with two searched sources, one
/// carrying a citation excerpt, plus a duplicate result item to exercise the
/// URL dedup.
fn sample_response() -> Json {
  {
    "content": [
      {
        "type": "server_tool_use",
        "id": "srvtoolu_1",
        "name": "web_search",
        "input": { "query": "moonbit language" },
      },
      {
        "type": "web_search_tool_result",
        "tool_use_id": "srvtoolu_1",
        "content": [
          {
            "type": "web_search_result",
            "url": "https://example.com/a",
            "title": "Example A",
            "page_age": "January 5, 2026",
          },
          { "type": "web_search_result", "url": "https://example.org/b" },
          {
            "type": "web_search_result",
            "url": "https://example.com/a",
            "title": "Example A duplicate",
          },
        ],
      },
      {
        "type": "text",
        "text": "According to Example A, MoonBit is fast.",
        "citations": [
          {
            "type": "citations_web_search_result_location",
            "url": "https://example.com/a",
            "cited_text": "MoonBit is a fast language.",
          },
        ],
      },
    ],
  }
}
