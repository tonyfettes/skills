# MoonBit Data Types: Primitives, Strings, Collections

Primitives (`Int`/`Char`/`Byte`), `Bytes`, the Array family, `String`/`StringView` (UTF-16 safety, interpolation, `<+`/`<?` streaming, multi-line), `Map`, and view types. Split out of `language.md` — for structs/enums/newtypes and everything else, see `language.md`.

## Primitives: Int, Char, Byte

MoonBit supports `Byte`, `Int16`, `Int`, `UInt16`, `UInt`, `Int64`, `UInt64`, `Float`, `Double`, etc. Literals overload when the type is known:

```mbt check
///|
test "integer/char literal overloading via context" {
  let a0 = 1 // Int by default
  let (int, uint, uint16, int64, byte) : (Int, UInt, UInt16, Int64, Byte) = (
    1, 1, 1, 1, 1,
  )
  assert_eq(int, uint16.to_int())
  let a1 : Int = 'b'    // unicode value
  let a2 : Char = 'b'
}
```

### `Char` ASCII casing

For ASCII-only casing, use:

- `Char::to_ascii_lowercase`
- `Char::to_ascii_uppercase`

If you need full Unicode case conversion or locale-sensitive text transforms,
do not guess or hand-roll it. Use a dedicated library only after confirming
with the user.

## Bytes (immutable)

```mbt check
///|
test "bytes literals and indexing" {
  let b0 : Bytes = b"abcd"
  let b1 : Bytes = "abcd"                   // b" prefix optional when type known
  let b2 : Bytes = [0xff, 0x00, 0x01]       // array literal overloading
  guard b0 is [b'a', ..] && b0[1] is b'b' else {
    fail("unexpected bytes content")
  }
}
```

## Array (resizable), FixedArray, ReadOnlyArray, ArrayView

```mbt check
///|
test "array literals" {
  let a0 : Array[Int] = [1, 2, 3]           // resizable
  let a1 : FixedArray[Int] = [1, 2, 3]      // fixed size
  let a2 : ReadOnlyArray[Int] = [1, 2, 3]
  let a3 : ArrayView[Int] = [1, 2, 3]
}
```

## String (immutable UTF-16)

`s[i]` returns a **code unit (UInt16)** — NOT a Char. Use `s.get_char(i)` for `Char?`.

```mbt check
///|
test "string indexing and utf8 encode/decode" {
  let s = "hello world"
  let b0 : UInt16 = s[0]
  guard b0 is ('\n' | 'h' | 'b' | 'a'..='z') && s is [.. "hello", .. rest] else {
    fail("unexpected string content")
  }
  guard rest is " world"                   // crashes on mismatch (no `else`)

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

## Map (mutable, insertion-order preserving)

```mbt check
///|
test "map literals and common operations" {
  let map : Map[String, Int] = { "a": 1, "b": 2, "c": 3 }
  let empty : Map[String, Int] = {}                     // preferred over Map::new()
  let also_empty : Map[String, Int] = Map::new()
  let from_pairs : Map[String, Int] = Map::from_array([("x", 1), ("y", 2)])

  map["new-key"] = 3
  map["a"] = 10

  guard map is { "new-key": 3, "missing"? : None, .. } else {
    fail("unexpected map")
  }
  let value : Int = map["a"]                 // panics if missing

  for k, v in map {
    println("\{k}: \{v}")                    // insertion order preserved
  }

  map.remove("b")
  guard map is { "a": 10, "c": 3, "new-key": 3, .. } && map.length() == 3 else {
    fail("unexpected map after removal")
  }
}
```

## View types

Zero-copy, non-owning read-only slices created with `[:]` syntax. No allocation. Functions taking `String`/`Bytes`/`Array` also accept `*View` (implicit conversion).

- `String` → `StringView` via `s[:]`, `s[start:end]`, `s[start:]`, `s[:end]`
- `Bytes` → `BytesView` via `b[:]`, `b[start:end]`, etc.
- `Array[T]` / `FixedArray[T]` / `ReadOnlyArray[T]` → `ArrayView[T]` via `a[:]`, etc.

**StringView caveat**: `s[a:b]` may raise at surrogate boundaries (UTF-16 edge case). Use `try! s[a:b]` if certain, or propagate the error.

Use views for:
- Rest patterns (`[first, .. rest]`)
- Passing slices without allocation
- Avoiding copies of large sequences

Convert back with `.to_string()`, `.to_bytes()`, `.to_array()` when you need ownership.
