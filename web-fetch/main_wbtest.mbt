///|
fn opts_of(result : ParseResult) -> Opts raise {
  match result {
    Parsed(opts) => opts
    _ => fail("expected the arguments to parse")
  }
}

///|
test "parse_args defaults to the auto backend" {
  let opts = opts_of(parse_args(["--links", "https://example.com/"]))
  assert_true(opts.backend is Auto)
  assert_true(opts.links)
  assert_eq(opts.base_url, @deepseek.DEFAULT_BASE_URL)
  assert_eq(opts.api_key, None)
  assert_eq(opts.user_agent, "tonyfettes/skills-web-fetch/0.2")
}

///|
test "parse_args reads the backend selector" {
  assert_true(
    opts_of(parse_args(["--backend", "local", "https://e.com/"])).backend
    is Local,
  )
  assert_true(
    opts_of(parse_args(["--backend", "deepseek", "https://e.com/"])).backend
    is DeepSeek,
  )
  assert_true(
    opts_of(parse_args(["--backend", "auto", "https://e.com/"])).backend is Auto,
  )
}

///|
test "an unknown backend is a usage error" {
  match parse_args(["--backend", "bogus", "https://e.com/"]) {
    UsageError(message) => assert_true(message.contains("unknown backend"))
    _ => fail("expected a usage error")
  }
}

///|
test "an option missing its value is a usage error" {
  for flag in ["--backend", "--api-key", "--base-url", "--text", "--max"] {
    match parse_args([flag]) {
      UsageError(message) => assert_true(message.contains(flag))
      _ => fail("expected a usage error for \{flag}")
    }
  }
}

///|
test "raw selects the local backend on its own" {
  let opts = opts_of(parse_args(["--raw", "https://e.com/"]))
  assert_true(opts.raw)
  assert_true(opts.backend is Local)
  let explicit = opts_of(
    parse_args(["--raw", "--backend", "local", "https://e.com/"]),
  )
  assert_true(explicit.backend is Local)
}

///|
test "raw with an explicit deepseek backend is refused" {
  match parse_args(["--raw", "--backend", "deepseek", "https://e.com/"]) {
    UsageError(message) => assert_true(message.contains("--raw"))
    _ => fail("expected a usage error")
  }
}

///|
test "parse_args carries the api key and base url" {
  let opts = opts_of(
    parse_args([
      "--api-key", "k", "--base-url", "https://proxy.example", "https://e.com/",
    ]),
  )
  assert_eq(opts.api_key, Some("k"))
  assert_eq(opts.base_url, "https://proxy.example")
}

///|
test "resolve_api_key prefers the explicit key" {
  let opts = opts_of(parse_args(["--api-key", "explicit", "https://e.com/"]))
  assert_eq(resolve_api_key(opts), Some("explicit"))
}

///|
test "non_blank treats a blank value as absent" {
  assert_eq(non_blank(Some("")), None)
  assert_eq(non_blank(Some("   ")), None)
  assert_eq(non_blank(Some(" k ")), Some("k"))
  assert_eq(non_blank(None), None)
}
