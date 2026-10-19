///|
/// Resolve `ref_` (a relative URL or fragment reference) against the absolute
/// URL `base`. Returns `None` for empty, fragment-only, or non-HTTP(S)
/// references. `base` must itself be an absolute `http(s)://` URL.
pub fn absolute_url(base : String, ref_ : String) -> String? {
  if ref_.is_empty() {
    return None
  }
  // Drop any fragment; a bare "#frag" or "#" is not a fetchable URL.
  let mut reference = ref_
  if reference.find("#") is Some(sharp) {
    reference = reference[:sharp].to_owned()
  }
  if reference.is_empty() {
    return None
  }
  let lower = reference.to_lower()
  if lower.has_prefix("http://") || lower.has_prefix("https://") {
    return Some(reference)
  }
  // Protocol-relative: "//host/path"
  if lower.has_prefix("//") {
    match split_base(base) {
      Some((scheme, _, _)) => return Some(scheme + ":" + reference)
      None => return None
    }
  }
  // Any other scheme ("mailto:", "data:", "ftp://", ...) is out of scope.
  if reference.find("://") is Some(_) {
    return None
  }
  let first = reference[:first_sep(reference)].to_lower()
  if first.contains(":") {
    return None
  }
  match split_base(base) {
    None => None
    Some((_, origin, path)) =>
      if reference.has_prefix("/") {
        Some(origin + normalize_path(reference))
      } else {
        let dir = if path.find("/") is Some(_) {
          path[:last_index_of_slash(path) + 1].to_owned()
        } else {
          "/"
        }
        Some(origin + normalize_path(dir + reference))
      }
  }
}

///|
fn last_index_of_slash(s : String) -> Int32 {
  let mut result = -1
  for i in 0..<s.length() {
    if s[i] == '/' {
      result = i
    }
  }
  result
}

///|
fn first_sep(s : String) -> Int32 {
  match s.find("/") {
    Some(i) =>
      match s.find("?") {
        Some(q) => if q < i { q } else { i }
        None => i
      }
    None =>
      match s.find("?") {
        Some(q) => q
        None => s.length()
      }
  }
}

///|
/// Split an absolute URL into (scheme, origin, path). Path keeps its leading
/// "/" and has any query string removed.
fn split_base(base : String) -> (String, String, String)? {
  guard base.find("://") is Some(sep) else { return None }
  let scheme = base[:sep].to_owned().to_lower()
  guard scheme == "http" || scheme == "https" else { return None }
  let rest = base[sep + 3:]
  let auth_end = match rest.find("/") {
    Some(i) => i
    None => rest.length()
  }
  let authority = rest[:auth_end].to_owned()
  let mut path = if auth_end < rest.length() {
    rest[auth_end:].to_owned()
  } else {
    ""
  }
  if path.find("?") is Some(q) {
    path = path[:q].to_owned()
  }
  if path.is_empty() {
    path = "/"
  }
  Some((scheme, scheme + "://" + authority, path))
}

///|
/// Remove "." and ".." segments from an absolute path that starts with "/".
fn normalize_path(path : String) -> String {
  let stack : Array[String] = []
  for segment in path.split("/") {
    let seg = segment.to_owned()
    if seg == "." || seg.is_empty() {
      continue
    }
    if seg == ".." {
      if !stack.is_empty() {
        let _ = stack.pop()
      }
      continue
    }
    stack.push(seg)
  }
  "/" + stack.join("/")
}
