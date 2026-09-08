///|
/// Live check against the real DeepSeek Anthropic-compatible endpoint. Runs
/// only when the `DEEPSEEK` key is exported; prints a skip notice otherwise.
/// Only the SHAPE is stable, not the contents: which URLs surface, whether
/// titles/snippets/dates are present, and whether the cap truncates all drift
/// between runs.
async test "realworld web_search performs a native search against DeepSeek" {
  guard @env.get_env_var("DEEPSEEK") is Some(api_key) && api_key != "" else {
    println(
      "DEEPSEEK environment variable is not set or is empty; skipping realworld web_search test",
    )
    return
  }
  let outcome = perform_search(api_key~, "MoonBit programming language")
  // A real search must return at least one citeable source with a markdown
  // link; the URL itself is provider-chosen, only the shape is stable.
  assert_true(outcome.sources.length() > 0)
  assert_true(format_output(outcome).contains("](https://"))
}
