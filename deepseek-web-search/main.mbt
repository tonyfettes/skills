///|
priv struct Opts {
  queries : Array[String]
  api_key : String?
  base_url : String
  model : String
  max_results : Int
  max_uses : Int
  max_tokens : Int
  timeout_ms : Int
  read_stdin : Bool
}

///|
priv enum ParseResult {
  Parsed(Opts)
  PrintHelp
  UsageError(String)
}

///|
fn usage() -> String {
  let text =
    #|usage: moonx tonyfettes/skills-deepseek-web-search [options] <query> [...]
    #|
    #|Search the web through DeepSeek's native web search and print a bounded,
    #|citeable source list. The DeepSeek API key comes from the DEEPSEEK
    #|environment variable or --api-key.
    #|
    #|options:
    #|  --api-key <key>     DeepSeek API key (default: $DEEPSEEK)
    #|  --base-url <url>    Anthropic-compatible Messages base (default: DeepSeek /anthropic/v1)
    #|  --model <name>      auxiliary search model (default: deepseek-v4-flash)
    #|  --max-results <n>   cap on sources per query (default 8)
    #|  --max-uses <n>      native web_search tool uses per query (default 5)
    #|  --max-tokens <n>    generated-token cap for the search call (default 4096)
    #|  --timeout-ms <n>    wall timeout for one search call (default 120000)
    #|  --stdin             additionally read one query per line from stdin
    #|  -h, --help          show this help
  text
}

///|
fn parse_int_arg(v : String) -> Int? {
  let n : Int = @string.from_str(v) catch { _ => return None }
  Some(n)
}

///|
fn is_flag_arg(s : String) -> Bool {
  s.has_prefix("-")
}

///|
fn looks_like_program_path(s : String) -> Bool {
  s.contains("/") ||
  s.contains("\\") ||
  s.contains(".exe") ||
  s.contains(".wasm")
}

///|
/// Some runners pass argv[0] (the program path) as the first argument, others
/// do not. Drop a leading non-option token that looks like a path so both
/// invocation styles work.
fn args_without_program(args : Array[String]) -> Array[String] {
  if args.is_empty() {
    return args
  }
  let first = args[0]
  if is_flag_arg(first) || !looks_like_program_path(first) {
    return args
  }
  let rest : Array[String] = []
  for i in 1..<args.length() {
    rest.push(args[i])
  }
  rest
}

///|
fn parse_args(raw_args : Array[String]) -> ParseResult {
  let args = args_without_program(raw_args)
  let queries : Array[String] = []
  let mut api_key : String? = None
  let mut base_url = @search.DefaultBaseUrl
  let mut model = @search.DefaultSearchModel
  let mut max_results = @search.DefaultMaxResults
  let mut max_uses = @search.DefaultMaxUses
  let mut max_tokens = @search.DefaultMaxTokens
  let mut timeout_ms = @search.DefaultTimeoutMs
  let mut read_stdin = false
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      return PrintHelp
    }
    if arg == "--stdin" {
      read_stdin = true
    } else if arg == "--api-key" ||
      arg == "--base-url" ||
      arg == "--model" ||
      arg == "--max-results" ||
      arg == "--max-uses" ||
      arg == "--max-tokens" ||
      arg == "--timeout-ms" {
      if i + 1 >= args.length() {
        return UsageError("missing value for \{arg}")
      }
      i = i + 1
      let value = args[i]
      match arg {
        "--api-key" => api_key = Some(value)
        "--base-url" => base_url = value
        "--model" => model = value
        "--max-results" =>
          match parse_int_arg(value) {
            Some(n) =>
              if n > 0 {
                max_results = n
              } else {
                return UsageError("--max-results must be positive")
              }
            None => return UsageError("invalid --max-results value: \{value}")
          }
        "--max-uses" =>
          match parse_int_arg(value) {
            Some(n) =>
              if n > 0 {
                max_uses = n
              } else {
                return UsageError("--max-uses must be positive")
              }
            None => return UsageError("invalid --max-uses value: \{value}")
          }
        "--max-tokens" =>
          match parse_int_arg(value) {
            Some(n) =>
              if n > 0 {
                max_tokens = n
              } else {
                return UsageError("--max-tokens must be positive")
              }
            None => return UsageError("invalid --max-tokens value: \{value}")
          }
        "--timeout-ms" =>
          match parse_int_arg(value) {
            Some(n) =>
              if n > 0 {
                timeout_ms = n
              } else {
                return UsageError("--timeout-ms must be positive")
              }
            None => return UsageError("invalid --timeout-ms value: \{value}")
          }
        _ => ()
      }
    } else if arg.has_prefix("--") {
      return UsageError("unknown option: \{arg}")
    } else {
      if arg.is_blank() {
        return UsageError("blank query")
      }
      if arg.length() > @search.MaxQueryChars {
        return UsageError(
          "query exceeds \{@search.MaxQueryChars} chars — ask one focused question",
        )
      }
      queries.push(arg)
    }
    i = i + 1
  }
  if queries.is_empty() && !read_stdin {
    return UsageError("no queries given")
  }
  Parsed({
    queries,
    api_key,
    base_url,
    model,
    max_results,
    max_uses,
    max_tokens,
    timeout_ms,
    read_stdin,
  })
}

///|
fn print_bounded(s : String, limit : Int) -> Unit {
  if s.length() > limit {
    println(s[:limit].to_owned() + "\n[...]")
  } else {
    println(s)
  }
}

///|
async fn run_one(opts : Opts, query : String, multiple : Bool) -> Bool {
  let key = match opts.api_key {
    Some(key) => key
    None =>
      match @env.get_env_var("DEEPSEEK") {
        Some(key) if key != "" => key
        _ => {
          println("error: no DeepSeek API key: set DEEPSEEK or pass --api-key")
          return true
        }
      }
  }
  let outcome = @search.perform_search(
    api_key=key,
    base_url=opts.base_url,
    model=opts.model,
    max_results=opts.max_results,
    max_uses=opts.max_uses,
    max_tokens=opts.max_tokens,
    timeout_ms=opts.timeout_ms,
    query,
  ) catch {
    @search.SearchFailure(message) => {
      println("error: \{message}")
      return true
    }
    _ => {
      println("error: web_search failed for: \{query}")
      return true
    }
  }
  if multiple {
    println("== \{query} ==")
  }
  print_bounded(@search.format_output(outcome), 6000)
  false
}

///|
async fn collect_queries(opts : Opts) -> Array[String] {
  if !opts.read_stdin {
    return opts.queries
  }
  let all = opts.queries
  let content = @stdio.stdin.read_all().text() catch { _ => "" }
  for line in content.split("\n") {
    let query = line.trim().to_owned()
    if !query.is_empty() && query.length() <= @search.MaxQueryChars {
      all.push(query)
    }
  }
  all
}

///|
async fn main {
  match parse_args(@env.args()) {
    PrintHelp => println(usage())
    UsageError(message) => {
      println("skills-deepseek-web-search: error: \{message}")
      println("")
      println(usage())
      @sys.exit(2)
    }
    Parsed(opts) => {
      let queries = collect_queries(opts)
      if queries.is_empty() {
        println("skills-deepseek-web-search: error: no non-blank queries given")
        println("")
        println(usage())
        @sys.exit(2)
      }
      let multiple = queries.length() > 1
      let mut failed = false
      for query in queries {
        if run_one(opts, query, multiple) {
          failed = true
        }
      }
      if failed {
        @sys.exit(1)
      }
    }
  }
}
