///|
priv struct Opts {
  urls : Array[String]
  raw : Bool
  links : Bool
  read_stdin : Bool
  max_bytes : Int
  text_limit : Int
  user_agent : String
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
    #|Fetch web pages and print their content. HTML pages are reduced to their
    #|title and main text; other responses are printed raw. Body size is capped
    #|with --max so a huge download cannot flood the output.
    #|
    #|options:
    #|  --raw          print the raw response body instead of extracting text
    #|  --links        also list absolute links found on HTML pages
    #|  --stdin        additionally read one URL per line from stdin
    #|  --max <bytes>  cap the response body size (default 2000000)
    #|  --text <chars> cap extracted or printed text (default 400000)
    #|  --ua <string>  set the User-Agent header
    #|  -h, --help     show this help
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
  let mut user_agent = "tonyfettes/skills-web-fetch/0.1"
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
  Parsed({ urls, raw, links, read_stdin, max_bytes, text_limit, user_agent, })
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
async fn run_one(opts : Opts, url : String, multiple : Bool) -> Bool {
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
      let urls = collect_urls(opts)
      let multiple = urls.length() > 1
      let mut failed = false
      for url in urls {
        if run_one(opts, url, multiple) {
          failed = true
        }
      }
      if failed {
        @sys.exit(1)
      }
    }
  }
}
