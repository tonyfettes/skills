# MoonBit Bytes & Binary Data

`Bytes` (immutable), `b"..."` literals, choosing a byte container
(`Buffer()`, `MutArrayView[Byte]`), `BytesView`, and bitstring patterns for
binary parsing. `ArrayView`/view mechanics are in `collections.md`; wire-format
FFI buffers are in `c-ffi.md` / `ffi-js-wasm.md`.

## Bytes (immutable)

```mbt check
///|
test "bytes literals and indexing" {
  let b0 : Bytes = b"abcd"
  let b1 : Bytes = b"abcd"                  // always use the b" prefix (bare string literal as Bytes is deprecated)
  let b2 : Bytes = [0xff, 0x00, 0x01]       // array literal overloading
  guard b0 is [b'a', ..] && b0[1] is b'b' else {
    fail("unexpected bytes content")
  }
}
```

### Choosing a byte container

| Type | Ownership / mutability | Resizable | Typical use |
|---|---|---|---|
| `Bytes` | owned, immutable | no | final payloads, API boundaries |
| `BytesView` | borrowed, immutable | no | slicing/parsing without copying |
| `Array[Byte]` | owned, mutable | yes | general mutable byte storage |
| `FixedArray[Byte]` | owned, mutable | no | fixed-size working buffers |
| `ArrayView[Byte]` / `MutArrayView[Byte]` | borrowed view | no | passing / mutating slices in place |
| `@buffer.Buffer` | owned, mutable builder | yes | incremental construction, then `contents()` |

`MutArrayView[Byte]` comes from `data.mut_view(...)` and writes through to the
underlying array; `Buffer()` (the prelude constructor — `@buffer.new()` is
deprecated) accumulates writes and yields `Bytes`:

```mbt check
///|
test "mutable byte storage" {
  let data : Array[Byte] = [b'a', b'b', b'c', b'd']
  let mv : MutArrayView[Byte] = data.mut_view(start=1, end=3)
  mv[0] = b'X'                          // writes through to `data`
  assert_true(data[1] is b'X')

  let buf = Buffer()                    // @buffer.new() is deprecated
  buf.write_byte(b'h')
  buf.write_bytes(b"i!")
  let out : Bytes = buf.contents()
  assert_true(out is b"hi!")
}
```


## Bitstring patterns (binary parsing)

Match packed bit fields out of `Bytes` / `BytesView` / `Array[Byte]` / `FixedArray[Byte]` / `ArrayView[Byte]` with `u`/`i` (unsigned/signed) + bit width + endianness suffix. `be` allows widths 1..64; `le` only byte-aligned widths (8·n). Without a trailing `..`, the pattern must consume the whole view:

```mbt check
///|
test "bitstring patterns" {
  let packet : Bytes = b"\xD2\x10"
  match packet[:] {
    // 1 + 3 + 4 + 8 = 16 bits — consumes both bytes exactly
    [u1be(flag), u3be(kind), u4be(version), u8be(length)] => {
      assert_eq(flag, 1)
      assert_eq(kind, 0b101)
      assert_eq(version, 0b0010)
      assert_eq(length, 16)
    }
    _ => fail("bad header")
  }
  // literal bit patterns validate headers; `..` captures the rest
  guard b"\xF1\xAA"[:] is [u4be(0b1111), u4be(tag), .. _rest] else { fail("bad prefix") }
  assert_eq(tag, 1)
  // signed = two's complement: i1be yields 0 or -1
  guard b"\x80"[:] is [i1be(i), ..] else { fail("i1be") }
  assert_eq(i, -1)
}
```

Result type depends on width: 1..32 bits → `Int`/`UInt`; 33..64 bits → `Int64`/`UInt64`.

---

