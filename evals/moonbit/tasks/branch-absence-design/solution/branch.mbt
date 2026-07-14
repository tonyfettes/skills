///|
/// Branch name `git rev-parse --abbrev-ref HEAD` prints inside `repo`, or
/// `None` when the command fails (not a git repository, detached worktree
/// removed, ...).
pub fn current_branch(repo : String) -> String? {
  let result = run_proc("git", ["rev-parse", "--abbrev-ref", "HEAD"], cwd=repo)
  guard result.code == 0 else { return None }
  Some(result.stdout.trim().to_owned())
}
