///|
/// Result of running one external command.
pub struct ProcResult {
  code : Int
  stdout : String
}

///|
/// Scripted stand-in for running external commands (tests run no real
/// processes). For `git rev-parse --abbrev-ref HEAD` it knows these repos:
///
///   "/repo/main"    — exits 0, prints "main\n"
///   "/repo/feature" — exits 0, prints "feature/login\n"
///   "/repo/broken"  — exits 128, prints nothing (not a git repository)
///
/// Any other cwd exits 1 with no output; any other command exits 127.
/// DO NOT MODIFY THIS FILE — it is restored before grading.
pub fn run_proc(cmd : String, args : Array[String], cwd~ : String) -> ProcResult {
  guard cmd == "git" && args is ["rev-parse", "--abbrev-ref", "HEAD"] else {
    return { code: 127, stdout: "" }
  }
  match cwd {
    "/repo/main" => { code: 0, stdout: "main\n" }
    "/repo/feature" => { code: 0, stdout: "feature/login\n" }
    "/repo/broken" => { code: 128, stdout: "" }
    _ => { code: 1, stdout: "" }
  }
}
