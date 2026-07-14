///|
test "healthy repos report their branch" {
  @debug.assert_eq(@vcs.current_branch("/repo/main"), Some("main"))
  @debug.assert_eq(@vcs.current_branch("/repo/feature"), Some("feature/login"))
}

///|
test "broken repo reports no branch" {
  @debug.assert_eq(@vcs.current_branch("/repo/broken"), None)
}
