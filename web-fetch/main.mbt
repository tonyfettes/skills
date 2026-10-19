///|
/// Which fetch implementation a run uses.
priv enum Backend {
  /// DeepSeek Fetch when an API key resolves, the local fetcher otherwise.
  Auto
  /// DeepSeek Fetch only; a missing key is a usage error.
  DeepSeek
  /// The local fetcher only: one HTTP GET, HTML reduced to title and text.
  Local
}

///|
priv struct Opts {
  urls : Array[String]
  raw : Bool
  links : Bool
  read_stdin : Bool
  max_bytes : Int32
  text_limit : Int32
  user_agent : String
  backend : Backend
  api_key : String?
  base_url : String
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
    #|usage: moonx tonyfettes/skills-web-fetch [options] <url> [...]
    #|
    #|Fetch web pages and print their content. With a DeepSeek API key the page
    #|comes from the DeepSeek Fetch API as Markdown; otherwise a local fetch
    #|reduces HTML to its title and main text and prints other responses raw.
    #|
    #|options:
    #|  --backend <name>  auto (default), deepseek, or local
    #|  --api-key <key>   DeepSeek API key (default: $DEEPSEEK, then
    #|                    $DEEPSEEK_API_KEY)
    #|  --base-url <url>  DeepSeek API base (default https://api.deepseek.com)
    #|  --raw             print the raw response body instead of extracting text
    #|                    (local backend only; implies --backend local)
    #|  --links           also list the absolute links a page contains
    #|  --stdin           additionally read one URL per line from stdin
    #|  --max <bytes>     cap the local response body size (default 2000000)
    #|  --text <chars>    cap extracted or printed text (default 400000)
    #|  --ua <string>     set the User-Agent header of the local fetcher
    #|  -h, --help        show this help
  text
}

///|
fn parse_int_arg(v : String) -> Int32? {
  let n : Int32 = @string.from_str(v) catch { _ => return None }
  Some(n)
}

///|
fn is_flag_arg(s : String) -> Bool {
  s.has_prefix("-")
}

///|
fn is_url_arg(s : String) -> Bool {
  s.contains("://")
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
/// do not. Drop a leading non-option, non-URL token that looks like a path so
/// both invocation styles work.
fn args_without_program(args : Array[String]) -> Array[String] {
  if args.is_empty() {
    return args
  }
  let first = args[0]
  if is_flag_arg(first) || is_url_arg(first) || !looks_like_program_path(first) {
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
  let urls : Array[String] = []
  let mut raw = false
  let mut links = false
  let mut read_stdin = false
  let mut max_bytes = 2_000_000
  let mut text_limit = 400_000
  let mut user_agent = "tonyfettes/skills-web-fetch/0.2"
  let mut backend = Auto
  let mut api_key : String? = None
  let mut base_url = @deepseek.DEFAULT_BASE_URL
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      return PrintHelp
    }
    if arg == "--raw" {
      raw = true
    } else if arg == "--links" {
      links = true
    } else if arg == "--stdin" {
      read_stdin = true
    } else if arg == "--backend" || arg == "--api-key" || arg == "--base-url" {
      if i + 1 >= args.length() {
        return UsageError("missing value for \{arg}")
      }
      i = i + 1
      let value = args[i]
      if arg == "--backend" {
        match value {
          "auto" => backend = Auto
          "deepseek" => backend = DeepSeek
          "local" => backend = Local
          _ =>
            return UsageError(
              "unknown backend: \{value} (expected auto, deepseek, or local)",
            )
        }
      } else if arg == "--api-key" {
        api_key = Some(value)
      } else {
        base_url = value
      }
    } else if arg == "--max" || arg == "--text" || arg == "--ua" {
      if i + 1 >= args.length() {
        return UsageError("missing value for \{arg}")
      }
      i = i + 1
      let value = args[i]
      if arg == "--max" {
        match parse_int_arg(value) {
          Some(n) =>
            if n > 0 {
              max_bytes = n
            } else {
              return UsageError("--max must be positive")
            }
          None => return UsageError("invalid --max value: \{value}")
        }
      } else if arg == "--text" {
        match parse_int_arg(value) {
          Some(n) =>
            if n > 0 {
              text_limit = n
            } else {
              return UsageError("--text must be positive")
            }
          None => return UsageError("invalid --text value: \{value}")
        }
      } else {
        user_agent = value
      }
    } else if arg.has_prefix("--") {
      return UsageError("unknown option: \{arg}")
    } else {
      urls.push(arg)
    }
    i = i + 1
  }
  if urls.is_empty() && !read_stdin {
    return UsageError("no URLs given")
  }
  // The DeepSeek backend returns Markdown, not the response bytes, so `--raw`
  // can only be honoured locally: it selects that backend instead of being
  // silently ignored, and combining it with an explicit DeepSeek request is
  // reported rather than quietly downgraded.
  if raw {
    match backend {
      DeepSeek =>
        return UsageError(
          "--raw prints the raw response body, which the DeepSeek backend does not return; use --backend local",
        )
      Auto => backend = Local
      Local => ()
    }
  }
  Parsed({
    urls,
    raw,
    links,
    read_stdin,
    max_bytes,
    text_limit,
    user_agent,
    backend,
    api_key,
    base_url,
  })
}

///|
fn print_bounded(s : String, limit : Int32) -> Unit {
  if s.length() > limit {
    println(s[:limit].to_owned() + "\n[...]")
  } else {
    println(s)
  }
}

///|
fn print_page(opts : Opts, page : @fetch.Page, multiple : Bool) -> Unit {
  if opts.raw {
    if multiple {
      println("== \{page.url} ==")
    }
    println(page.body)
    return
  }
  if multiple {
    println("== \{page.url} ==")
  }
  if @fetch.looks_like_html(page.content_type, page.body) {
    let article = @extract.extract_article(page.body, page.url)
    if !article.title.is_empty() {
      println("Title: \{article.title}")
    }
    if !article.text.is_empty() {
      println("")
      print_bounded(article.text, opts.text_limit)
    } else {
      println("")
      println("(no readable text found)")
    }
    if opts.links && !article.links.is_empty() {
      println("")
      println("Links:")
      for pair in article.links {
        println("- \{pair.0}: \{pair.1}")
      }
    }
  } else {
    print_bounded(page.body, opts.text_limit)
  }
}

///|
async fn run_one(
  opts : Opts,
  backend : Resolved,
  url : String,
  multiple : Bool,
) -> Bool {
  match backend {
    ViaLocal => run_one_local(opts, url, multiple)
    ViaDeepSeek(api_key) => run_one_deepseek(opts, url, api_key, multiple)
  }
}

///|
async fn run_one_local(opts : Opts, url : String, multiple : Bool) -> Bool {
  let page = @fetch.fetch_page(
    url,
    max_bytes=opts.max_bytes,
    user_agent=opts.user_agent,
  ) catch {
    @fetch.FetchError::HttpStatus(code, final_url, reason) => {
      println("error: HTTP \{code} \{reason} for \{final_url}")
      return true
    }
    @fetch.FetchError::TooManyRedirects(final_url) => {
      println("error: too many redirects for \{final_url}")
      return true
    }
    @fetch.FetchError::RequestFailed(final_url, detail) => {
      println("error: \{detail} for \{final_url}")
      return true
    }
    @fetch.FetchError::NotText(final_url) => {
      println("error: response body is not valid UTF-8 text for \{final_url}")
      return true
    }
    _ => {
      println("error: unexpected failure while fetching \{url}")
      return true
    }
  }
  print_page(opts, page, multiple)
  false
}

///|
async fn collect_urls(opts : Opts) -> Array[String] {
  if !opts.read_stdin {
    return opts.urls
  }
  let all = opts.urls
  let content = @stdio.stdin.read_all().text() catch { _ => "" }
  for line in content.split("\n") {
    let url = line.trim().to_owned()
    if !url.is_empty() {
      all.push(url)
    }
  }
  all
}

///|
async fn main {
  match parse_args(@env.args()) {
    PrintHelp => println(usage())
    UsageError(message) => {
      println("skills-web-fetch: error: \{message}")
      println("")
      println(usage())
      @sys.exit(2)
    }
    Parsed(opts) => {
      let api_key = resolve_api_key(opts)
      if opts.backend is DeepSeek && api_key is None {
        println(
          "skills-web-fetch: error: the DeepSeek backend needs an API key ($DEEPSEEK, $DEEPSEEK_API_KEY, or --api-key)",
        )
        @sys.exit(2)
        return
      }
      let backend = if opts.backend is Local || api_key is None {
        ViaLocal
      } else {
        match api_key {
          Some(key) => ViaDeepSeek(key)
          None => ViaLocal
        }
      }
      let urls = collect_urls(opts)
      let multiple = urls.length() > 1
      let mut failed = false
      for url in urls {
        if run_one(opts, backend, url, multiple) {
          failed = true
        }
      }
      if failed {
        @sys.exit(1)
      }
    }
  }
}

///|
/// The backend a run actually uses, after the API key was resolved: the key is
/// carried here so no later step can disagree with the choice made once.
priv enum Resolved {
  ViaDeepSeek(String)
  ViaLocal
}

///|
fn non_blank(value : String?) -> String? {
  match value {
    Some(text) =>
      if text.trim().is_empty() {
        None
      } else {
        Some(text.trim().to_owned())
      }
    None => None
  }
}

///|
/// `--api-key`, then `$DEEPSEEK`, then `$DEEPSEEK_API_KEY`. A blank value is
/// treated as absent, so an exported empty variable cannot select the billed
/// backend by accident.
fn resolve_api_key(opts : Opts) -> String? {
  if non_blank(opts.api_key) is Some(key) {
    return Some(key)
  }
  if non_blank(@env.get_env_var("DEEPSEEK")) is Some(key) {
    return Some(key)
  }
  non_blank(@env.get_env_var("DEEPSEEK_API_KEY"))
}

///|
async fn run_one_deepseek(
  opts : Opts,
  url : String,
  api_key : String,
  multiple : Bool,
) -> Bool {
  let page = @deepseek.fetch_page(url, api_key, base_url=opts.base_url) catch {
    @deepseek.FetchError::InvalidUrl(reason) => {
      println("error: \{reason} for \{url}")
      return true
    }
    @deepseek.FetchError::HttpStatus(0, detail) => {
      println(
        "error: could not reach the DeepSeek Fetch API (\{opts.base_url}) for \{url}: \{detail}",
      )
      return true
    }
    @deepseek.FetchError::HttpStatus(code, detail) => {
      println("error: DeepSeek Fetch HTTP \{code} for \{url}: \{detail}")
      return true
    }
    @deepseek.FetchError::Malformed(detail) => {
      println("error: malformed DeepSeek Fetch response for \{url}: \{detail}")
      return true
    }
    _ => {
      println("error: unexpected failure while fetching \{url}")
      return true
    }
  }
  print_deepseek_page(opts, page, url, multiple)
  false
}

///|
/// The DeepSeek backend already returns Markdown, so it prints the same shape
/// the local backend produces: a `Title:` line, a blank line, then the text.
fn print_deepseek_page(
  opts : Opts,
  page : @deepseek.Page,
  url : String,
  multiple : Bool,
) -> Unit {
  if multiple {
    println("== \{url} ==")
  }
  if !page.title.is_empty() {
    println("Title: \{page.title}")
    println("")
  }
  print_bounded(page.content, opts.text_limit)
  if opts.links {
    let links = @deepseek.markdown_links(page.content)
    if !links.is_empty() {
      println("")
      println("Links:")
      for pair in links {
        println("- \{pair.0}: \{pair.1}")
      }
    }
  }
}
