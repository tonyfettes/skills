///|
test "status_reason covers the documented failures" {
  assert_eq(status_reason(0), "network or TLS failure")
  assert_eq(status_reason(400), "invalid request")
  assert_eq(status_reason(401), "invalid or missing API key")
  assert_eq(status_reason(402), "insufficient balance")
  assert_eq(status_reason(403), "rejected by the security policy")
  assert_eq(status_reason(404), "could not retrieve usable page content")
  assert_eq(status_reason(408), "request timed out")
  assert_eq(status_reason(413), "request body too large")
  assert_eq(status_reason(429), "rate limited")
  assert_eq(status_reason(500), "server error")
  assert_eq(status_reason(504), "upstream timeout")
  assert_eq(status_reason(418), "unexpected status")
}

///|
test "error_reason appends the provider message when there is one" {
  assert_eq(error_reason(404, ""), "could not retrieve usable page content")
  assert_eq(
    error_reason(
      400, "{\"error\":{\"message\":\"'count' must be between 1 and 50\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":\"invalid_request_error\"}}",
    ),
    "invalid request: 'count' must be between 1 and 50",
  )
  // A gateway answering with something that is not the documented error object
  // must not turn into an empty or garbled line.
  assert_eq(error_reason(429, "Too Many Requests"), "rate limited")
  assert_eq(error_reason(500, "{\"error\":{\"message\":\"\"}}"), "server error")
}

///|
test "trim_end_slash leaves one separator" {
  assert_eq(
    trim_end_slash("https://api.deepseek.com"),
    "https://api.deepseek.com",
  )
  assert_eq(
    trim_end_slash("https://api.deepseek.com/"),
    "https://api.deepseek.com",
  )
  assert_eq(
    trim_end_slash("https://proxy.example/ds//"),
    "https://proxy.example/ds",
  )
  assert_eq(trim_end_slash(""), "")
}
