///|
pub struct Article {
  title : String
  text : String
  links : Array[(String, String)]
}

///|
/// Parse an HTML document and pull out the readable content: a title, main
/// text, and a de-duplicated list of absolute links. When the document
/// contains a `<main>` or `<article>` element, extraction starts there;
/// otherwise the whole body is used.
pub fn extract_article(
  html : String,
  base_url : String,
  link_limit? : Int = 200,
) -> Article {
  let doc = @html.parse(html)
  let html_id = child_tag(doc, 0, "html")
  let head_id = child_tag(doc, html_id, "head")
  let body_id = child_tag(doc, html_id, "body")
  let mut title = ""
  if head_id >= 0 {
    let title_id = child_tag(doc, head_id, "title")
    if title_id >= 0 {
      title = collapse_ws(doc.get_text_content(title_id)).trim().to_owned()
    }
  }
  let root = if body_id >= 0 {
    let mainish = find_mainish(doc, body_id)
    if mainish >= 0 {
      mainish
    } else {
      body_id
    }
  } else {
    html_id
  }
  let text = collect_text(doc, root).join("\n\n")
  if title.is_empty() {
    let h1 = find_first_tag(doc, root, "h1")
    if h1 >= 0 {
      title = collapse_ws(doc.get_text_content(h1)).trim().to_owned()
    }
  }
  let links = if base_url.is_empty() {
    []
  } else {
    collect_links(doc, root, base_url, link_limit)
  }
  { title, text, links, }
}

///|
fn child_tag(doc : @html.Document, parent : Int, tag : String) -> Int {
  if parent < 0 {
    return -1
  }
  for child in doc.get_children(parent) {
    if doc.get_tag_name(child) is Some(t) && t == tag {
      return child
    }
  }
  -1
}

///|
/// Depth-first search for the first `<main>` or `<article>` element.
fn find_mainish(doc : @html.Document, id : Int) -> Int {
  match doc.get_tag_name(id) {
    Some(tag) => if tag == "main" || tag == "article" { return id } else { () }
    None => ()
  }
  for child in doc.get_children(id) {
    let found = find_mainish(doc, child)
    if found >= 0 {
      return found
    }
  }
  -1
}

///|
fn find_first_tag(doc : @html.Document, id : Int, tag : String) -> Int {
  if doc.get_tag_name(id) is Some(t) && t == tag {
    return id
  }
  for child in doc.get_children(id) {
    let found = find_first_tag(doc, child, tag)
    if found >= 0 {
      return found
    }
  }
  -1
}

///|
fn is_skip_tag(tag : String) -> Bool {
  match tag {
    "script"
    | "style"
    | "noscript"
    | "template"
    | "iframe"
    | "object"
    | "embed"
    | "svg"
    | "math"
    | "audio"
    | "video"
    | "canvas"
    | "head"
    | "textarea" => true
    _ => false
  }
}

///|
fn is_inline_tag(tag : String) -> Bool {
  match tag {
    "a"
    | "span"
    | "strong"
    | "em"
    | "b"
    | "i"
    | "u"
    | "s"
    | "small"
    | "sub"
    | "sup"
    | "code"
    | "kbd"
    | "samp"
    | "mark"
    | "label"
    | "abbr"
    | "cite"
    | "time"
    | "q"
    | "dfn"
    | "var"
    | "wbr" => true
    _ => false
  }
}

///|
fn heading_marks(tag : String) -> String {
  match tag {
    "h1" => "# "
    "h2" => "## "
    "h3" => "### "
    "h4" => "#### "
    "h5" => "##### "
    "h6" => "###### "
    _ => ""
  }
}

///|
priv struct TextCollector {
  doc : @html.Document
  lines : Array[String]
  cur : Array[String]
  prefix : Array[String]
}

///|
fn flush_line(c : TextCollector) -> Unit {
  if c.cur.is_empty() {
    return
  }
  let raw = c.cur.join("")
  let line = raw.trim().to_owned()
  if !line.is_empty() {
    let mark = c.prefix[0]
    if mark.is_empty() {
      c.lines.push(line)
    } else {
      c.lines.push(mark + line)
    }
  }
  c.cur.clear()
  c.prefix[0] = ""
}

///|
fn collect_text(doc : @html.Document, root : Int) -> Array[String] {
  if root < 0 {
    return []
  }
  let c : TextCollector = { doc, lines: [], cur: [], prefix: [""], }
  walk_text(c, root, false)
  flush_line(c)
  c.lines
}

///|
fn walk_text(c : TextCollector, id : Int, in_pre : Bool) -> Unit {
  match c.doc.get_tag_name(id) {
    None => {
      let s = c.doc.get_text_content(id)
      if s.is_empty() {
        return
      }
      c.cur.push(if in_pre { s } else { collapse_ws(s) })
    }
    Some(tag) => {
      if is_skip_tag(tag) {
        return
      }
      if tag == "br" {
        flush_line(c)
        return
      }
      let inline = is_inline_tag(tag)
      if !inline {
        flush_line(c)
      }
      let children = c.doc.get_children(id)
      if tag == "pre" {
        for child in children {
          walk_text(c, child, true)
        }
      } else if tag == "li" {
        c.prefix[0] = "- "
        for child in children {
          walk_text(c, child, in_pre)
        }
      } else if heading_marks(tag) != "" {
        c.prefix[0] = heading_marks(tag)
        for child in children {
          walk_text(c, child, in_pre)
        }
      } else {
        for child in children {
          walk_text(c, child, in_pre)
        }
      }
      if !inline {
        flush_line(c)
      }
    }
  }
}

///|
fn collect_links(
  doc : @html.Document,
  id : Int,
  base : String,
  limit : Int,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let seen : Map[String, Bool] = Map([])
  walk_links(doc, id, base, out, seen, limit)
  out
}

///|
fn walk_links(
  doc : @html.Document,
  id : Int,
  base : String,
  out : Array[(String, String)],
  seen : Map[String, Bool],
  limit : Int,
) -> Unit {
  if out.length() >= limit {
    return
  }
  match doc.get_tag_name(id) {
    None => return
    Some(tag) => {
      if is_skip_tag(tag) {
        return
      }
      if tag == "a" {
        match doc.get_attribute(id, "href") {
          Some(href) =>
            match @url.absolute_url(base, href) {
              Some(url) =>
                match seen.get(url) {
                  Some(_) => ()
                  None => {
                    seen[url] = true
                    let label = collapse_ws(doc.get_text_content(id))
                      .trim()
                      .to_owned()
                    if label.is_empty() {
                      out.push((url, url))
                    } else {
                      let label = if label.length() > 120 {
                        label[:120].to_owned() + "…"
                      } else {
                        label
                      }
                      out.push((label, url))
                    }
                  }
                }
              None => ()
            }
          None => ()
        }
      }
    }
  }
  for child in doc.get_children(id) {
    walk_links(doc, child, base, out, seen, limit)
  }
}

///|
fn is_ws_code(u : Int) -> Bool {
  u == 9 || u == 10 || u == 12 || u == 13 || u == 32 || u == 160
}

///|
/// Collapse every run of whitespace to a single space. Leading and trailing
/// whitespace are kept here (they separate adjacent inline fragments); the
/// caller trims whole lines instead.
fn collapse_ws(s : String) -> String {
  let buf = StringBuilder()
  let mut i = 0
  let n = s.length()
  while i < n {
    let u1 = s[i].to_int()
    if is_ws_code(u1) {
      while i < n && is_ws_code(s[i].to_int()) {
        i = i + 1
      }
      buf.write_char(' ')
      continue
    }
    if u1 >= 0xD800 && u1 <= 0xDFFF {
      if u1 <= 0xDBFF && i + 1 < n {
        let u2 = s[i + 1].to_int()
        if u2 >= 0xDC00 && u2 <= 0xDFFF {
          let cp = 0x10000 + ((u1 - 0xD800) << 10) + (u2 - 0xDC00)
          buf.write_char(Int::unsafe_to_char(cp))
          i = i + 2
          continue
        }
      }
      i = i + 1 // lone surrogate: drop
      continue
    }
    buf.write_char(Int::unsafe_to_char(u1))
    i = i + 1
  }
  buf.to_string()
}
