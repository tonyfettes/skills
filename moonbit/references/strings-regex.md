# MoonBit Strings & Regex

`String`/`StringView` (immutable UTF-16, slicing safety), interpolation
(`\{...}`, `<+`/`<?` streaming), multi-line strings, and regex
(`re"..."` literals, `=~` matching). Split out of the former `strings-data.md` —
Arrays/`Map`/`Iter`/views are in `collections.md`, `Bytes` in `bytes.md`,
primitives in `language.md`.

## String (immutable UTF-16)

Native-runtime/FFI invariant: `String` allocations include a trailing UTF-16
zero code unit that is not counted by `length()`. C `const char *` APIs should
receive `Bytes`, not `String`; encode with `moonbitlang/core/encoding/utf8`,
and the resulting `Bytes` already has its own trailing zero byte sentinel.

`s[i]` returns a **code unit (UInt16)** — NOT a Char. Use `s.get_char(i)` for `Char?`.

```mbt check
///|
test "string indexing and utf8 encode/decode" {
  let s = "hello world"
  let b0 : UInt16 = s[0]
  guard b0 is ('\n' | 'h' | 'b' | 'a'..='z') && s is [.. "hello", .. rest] else {
    fail("unexpected string content")
  }
  guard rest is " world" else {            // always write the else — even in tests,
    fail("unexpected suffix: \{rest}")     // raise via fail(...) instead of panicking
  }

  let b1 : Char? = s.get_char(0)
  assert_true(b1 is Some('a'..='z'))

  // ⚠️ variables don't work with direct indexing
  let eq_char : Char = '='
  // s[0] == eq_char // ❌ eq_char not a literal; s[0] is UInt16
  // Use: s[0] == '=' or s.get_char(0) == Some(eq_char)

  let bytes = @utf8.encode("中文")
  assert_true(bytes is [0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87])
  let s2 : String = @utf8.decode(bytes)
  assert_true(s2 is "中文")
  for c in "中文" {
    let _ : Char = c                        // unicode-safe iteration
    println("char: \{c}")
  }
}
```

### String interpolation && StringBuilder

`\{expr}` for interpolation; custom types must implement `Show`:

```mbt check
///|
test "string interpolation" {
  let name : String = "Moon"
  let config = { "cache": 123 }
  let version = 1.0
  println("Hello \{name} v\{version}")

  // Quoted map keys are allowed inside interpolation expressions.
  println("'cache' section: \{config["cache"]}")

  let sb = StringBuilder()
  sb <+ "[\{[ for x in [1, 2, 3] => "\{x}" ].join(",")}]"
  inspect(sb, content="[1,2,3]")

  let x = 42
  let streamed = StringBuilder()
  streamed <+ "hello \{x}"
  inspect(streamed, content="hello 42")
}
```

Expressions inside `\{}` must be single-line expressions. Nested
interpolations and string literals are supported, but line breaks inside `\{}`
are not.

### `<+` and `<?` macros for streaming interpolation

String interpolation can be streamed directly into a
`Logger`/`StringBuilder`-style writer with `<+`, or conditionally through an
optional writer with `<?`:

```mbt nocheck
writer <+ "hello \{x}"
writer <+ {"key1": value, "key2": value2}
lhs <? "hello \{x}"
lhs <? {"key1": value, "key2": value2}
```

This expands to calls on the writer:

```mbt nocheck
writer.write_string("hello ")
writer.write(x)
writer.write_object_begin()
writer.write_object_field("key1", value)
writer.write_object_field("key2", value2)
writer.write_object_end()
if lhs is Some(l) { l <+ "hello \{x}" }
```

Literal string segments use `write_string`; interpolated expressions use
`write`. For `<?`, `None` performs no write; `Some(writer)` applies the same
`<+` expansion to the wrapped writer. The right-hand side of `<+` and `<?`
must be a template string / multiline template string or a map object literal,
not an arbitrary expression.

The expansion is macro-style: it depends on how the writer type implements
`write_string` and `write` for template strings, plus `write_object_begin`,
`write_object_field`, and `write_object_end` for map object literals. Types
such as HTMLBuilder or JSONBuilder can support interpolation and streaming
with the same syntax but different semantics. Because MoonBit allows local
methods on foreign types, a package can adapt an existing writer type to this
syntax by adding those local writer methods.

### Multi-line strings

```mbt check
///|
test "multi-line string literals" {
  let a : String =
    #|Hello "world"
    #|World
    #|
  let b : String =
    $|Line 1 ""
    $|Line 2 \{1+2}
    $|
  // `#|` — no escape. `$|` — only escape `\{..}`.
  assert_eq(a, "Hello \"world\"\nWorld\n")
  assert_eq(b, "Line 1 \"\"\nLine 2 3\n")
}
```


## Regex: `re"..."` literals and `=~` matching

`re"..."` is a compile-time-checked regex literal of type `Regex`. It is an
ordinary expression: bind it, pass it, use it as a default argument, define it
as a `const`. Combine with `+` (sequence) and `|` (alternation). Backslashes
are **not** double-escaped: write `re"/\*"`, not `re"/\\*"`.

`input =~ regex` searches a `StringView` and returns `Bool`. The right-hand
side must be a regex **constant** expression (literal, named `const`, or
`+`/`|` combination of those — no runtime values). Binders work like `is`:
usable after `&&`, in the `if` true-branch, and after `guard ... else`.

```mbt check
///|
const IDENT_START : Regex = re"[A-Za-z_]"

///|
const IDENT : Regex = IDENT_START + re"[A-Za-z0-9_]*"

///|
test "regex literals and =~" {
  // first-class Regex value: execute() returns the first match
  let r : Regex = re"(?<id>[0-9]+)"
  guard r.execute("abc42def") is Some(m) else { fail("no match") }
  assert_true(m.named_group("id") is Some("42"))

  // =~ searches a StringView, returns Bool; anchors constrain position
  assert_true("zabc!" =~ re"abc")        // search-based: matches anywhere
  assert_true(!("zabc!" =~ re"^abc"))

  // binders: `as` for the match, before~/after~ for the surroundings
  if " let_name = 42 " =~ (IDENT as ident, before=head, after=tail) {
    assert_true(ident is "let_name")
    assert_true(head is " ")
    assert_true(tail is " = 42 ")
  } else {
    fail("expected identifier")
  }
  if "abc" =~ (re"b", before~, after~) { // shorthand binds `before`/`after`
    assert_true(before is "a" && after is "c")
  }

  // a single-char regex binds a Char, not a StringView
  if ("abc" : StringView) =~ (re"." as ch, after=rest) {
    assert_eq(ch, 'a')
    assert_true(rest is "bc")
  }

  // POSIX classes replace \d \s \w (unsupported)
  assert_true("a1" =~ re"[[:alpha:]][[:digit:]]")
  assert_true("HELLO" =~ re"(?i:hello)") // scoped case-insensitive
}

///|
fn classify(line : StringView) -> String {
  guard line =~ (re"^[[:space:]]*#", after=rest) else { return "code" }
  "comment:\{rest}"
}

///|
test "=~ in guard" {
  inspect(classify("  # hi"), content="comment: hi")
  inspect(classify("f()"), content="code")
}
```

Semantics and gotchas:

- **First-match, not longest-match** — both `Regex::execute` and `=~` return
  the first match from the search position. Longest-match mode does not exist
  (the deprecated `lexmatch ... with longest` had it; `=~` will not).
- **`\d` `\D` `\s` `\S` `\w` `\W` are NOT supported.** Use POSIX classes
  inside brackets: `[[:digit:]]`, `[[:space:]]`, `[[:word:]]`, `[[:alpha:]]`,
  `[[:xdigit:]]`; negate as `[^[:digit:]]`.
- `^`/`$` are non-multiline (whole-input) anchors. `.` matches any char
  including newline.
- Named groups `(?<id>...)` are engine metadata for `Regex::execute` /
  `MatchResult::named_group`; they do **not** introduce MoonBit binders — use
  `as` in `=~` for that.
- To match a literal `{` use `[{]`, not `\{` (reserved for future
  interpolation). `\xHH` byte escapes are unsupported; `\uXXXX`/`\u{...}`
  work. In char classes, escape a literal dash as `\-`.
- `\b`/`\B` work on first-class `Regex` values but not (yet) in `=~` constant
  contexts. No lookahead/lookbehind/backreferences.
- Quantifiers: `*` `+` `?` `{n}` `{n,}` `{n,m}` plus non-greedy `?` variants;
  groups `(...)`, `(?:...)`; alternation `|`.
- `lexmatch` / `lexmatch?` are deprecated — write new code with `=~`.
