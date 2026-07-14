///|
test "healthy repos report their branch" {
  @debug.assert_eq(@vcs.current_branch("/repo/main"), "main")
  @debug.assert_eq(@vcs.current_branch("/repo/feature"), "feature/login")
}

///|
test "broken repo fails instead of fabricating a branch" {
  try @vcs.current_branch("/repo/broken") |> ignore catch {
    _ => ()
  } noraise {
    branch => fail("expected a failure for the broken repo, got \{branch}")
  }
}
