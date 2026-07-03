# MoonBit Collections

The Array family (`Array`/`FixedArray`/`ReadOnlyArray` + views), `Map`,
view types, spread `..x`, and `Iter[T]`/`Iter2` iterators. Split out of the
former `strings-data.md` — `String` and regex are in `strings-regex.md`,
`Bytes` in `bytes.md`, primitives in `language.md`.

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

### `FixedArray::make` shares ONE initial value

`FixedArray::make(n, v)` puts the *same* `v` in every cell. For a reference
type (nested arrays, structs) every cell aliases one object — use
`FixedArray::makei` to create one per index:

```mbt check
///|
test "FixedArray::make shares one object" {
  let grid = FixedArray::make(2, FixedArray::make(2, 0))
  grid[0][0] = 1
  inspect(grid[1][0], content="1")      // ⚠️ both rows are the SAME inner array
  let ok = FixedArray::makei(2, _i => FixedArray::make(2, 0))
  ok[0][0] = 1
  inspect(ok[1][0], content="0")        // makei creates one object per index
}
```

### Spread `..x` in literals

Array, `String`, and `Bytes` literals can splice in any sequence that has an
`iter()` method yielding the right element type (arrays, views, strings,
`@list.List`, your own types):

```mbt check
///|
test "spread in literals" {
  let a1 : Array[Int] = [1, 2, 3]
  let a2 : FixedArray[Int] = [4, 5]
  let a : Array[Int] = [..a1, ..a2, 6]
  debug_inspect(a, content="[1, 2, 3, 4, 5, 6]")
  let hello : String = "Hello"
  let s : String = [..hello, ' ', ..("World".view()), '!']
  inspect(s, content="Hello World!")
  let b : Bytes = [..b"hi", ..b"hi"[0:1], 10]
  debug_inspect(b, content="<Bytes: [0x68, 0x69, 0x68, 0x0a]>")
}
```

This is the construction-side counterpart of the `..` rest pattern.


## Map (mutable, insertion-order preserving)

```mbt check
///|
test "map literals and common operations" {
  let map : Map[String, Int] = { "a": 1, "b": 2, "c": 3 }
  let empty : Map[String, Int] = {}                     // literal, preferred
  let also_empty : Map[String, Int] = Map([])           // Map::new() is deprecated; Map([], capacity=...) to presize
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

Convert back with `.to_owned()` when you need ownership (works on all view types). Do NOT use `.to_string()` (deprecated `Show` display path on views) or `.to_array()` for this — see the `trim`/`StringView` gotcha in `language.md` and `strings-regex.md`.


## Iterators: `Iter[T]` and `Iter2[A, B]`

`Iter[T]` is the built-in external iterator: `next()` returns `Some(value)`
and advances, `None` when done. Combinators that build a new `Iter` (`filter`,
`map`, `concat`, `take`, ...) are **lazy** — nothing runs and no intermediate
collection is allocated until a consumer (`each`, `fold`, `collect`, `count`)
pulls. Prefer passing an `Iter` between functions over passing the container.

`for x in e` desugars to `e.iter()`; `for k, v in e` desugars to
`e.iter2() : Iter2[A, B]`. Give a custom type an `iter()` (and/or `iter2()`)
method and it works with `for .. in` directly:

```mbt check
///|
priv struct Sensor {
  samples : Bytes
}

///|
fn Sensor::iter(self : Sensor) -> Iter[Byte] {
  let mut i = 0
  Iter::new(() => if i < self.samples.length() {
    let b = self.samples[i]
    i += 1
    Some(b)
  } else {
    None
  })
}

///|
test "iter protocol" {
  // lazy combinators: no intermediate arrays until collect()
  let out = [1, 2, 3, 4, 5]
    .iter()
    .filter(x => (x & 1) == 0)
    .map(x => x * 10)
    .collect()
  debug_inspect(out, content="[20, 40]")

  // custom type: an `iter()` method enables `for .. in`
  let s = Sensor::{ samples: b"ab" }
  let mut sum = 0
  for b in s {
    sum += b.to_int()
  }
  inspect(sum, content="195")

  // iter2(): two-binder iteration (Map yields key/value; Array yields index/elem)
  let m : Iter2[String, Int] = { "a": 1, "b": 2 }.iter2()
  let mut acc = 0
  for _, v in m {
    acc += v
  }
  inspect(acc, content="3")

  // single-pass: next() advances shared state; consumed iterators don't reset
  let it = [10, 20, 30].iter()
  debug_inspect(it.next(), content="Some(10)")
  debug_inspect(it.collect(), content="[20, 30]")
  debug_inspect(it.next(), content="None")
}
```

**Single-pass**: once consumed (via `next()`, `each`, `fold`, `collect`, ...)
an `Iter` cannot be reset — request a fresh one from the source to traverse
again.

