# MoonBit JS / Wasm / Wasm-GC FFI Reference

FFI for the non-C backends: `js`, `wasm` (linear memory), and `wasm-gc`. For the
native C backend (`extern "c"`, C stubs, `moonbit.h`, ownership), see `c.md`.

**Use this reference when**:
- Binding JavaScript APIs with `extern "js"` or `#module`
- Importing host functions or writing inline Wasm (`extern "wasm"`) for Wasm / Wasm-GC
- Passing MoonBit closures to a JS or Wasm host
- Exporting MoonBit functions to the host (`link` config in `moon.pkg`)
- Binding host constants/flags with constant enums

## Which backend FFI

| Target | Mechanism | Notes |
|---|---|---|
| `js` | `extern "js"` inline lambda, or `= "Module" "name"` import, or `#module` | Full JS interop; closures work natively |
| `wasm` | `= "module" "name"` host import, or `extern "wasm"` inline | Linear memory; refcounted; only numeric/ref types cross the boundary |
| `wasm-gc` | Same as `wasm` | Host GC reused; `String` can be a JS string via JS String Builtins |

Gate backend-specific files in `moon.pkg` so other targets still build, and
build/test with an explicit target (`moon build --target js`, `moon test --target wasm-gc`):

```
options(
  targets: {
    "ffi_js.mbt": ["js"],
    "ffi_wasm.mbt": ["wasm", "wasm-gc"],
  },
)
```

## JS backend

### Inline JS (`extern "js"`)

The body is a JS lambda after `=`, written with `#|` multiline strings. Parameter
count must match the MoonBit signature. Use `-> Unit` when the JS side returns nothing.

```mbt check
///|
extern "js" fn js_cos(d : Double) -> Double =
  #|(d) => Math.cos(d)

///|
extern "js" fn object_set(obj : JsObject, key : String, value : String) -> Unit =
  #|(obj, key, value) => { obj[key] = value }
```

Multi-statement bodies work — the lambda is pasted into the output verbatim:

```mbt check
///|
extern "js" fn try_parse(s : String) -> JsObject =
  #|(s) => {
  #|  try { return JSON.parse(s) } catch (e) { return null }
  #|}
```

Global-path import form: `fn name(..) = "Module" "func"` (no `extern` keyword,
no body) binds to `Module.func` in the JS global scope, e.g.
`fn cos(d : Double) -> Double = "Math" "cos"`.

### `#module` — import from a JS module

`#module("specifier")` generates a real module dependency: `import { name } from
"specifier"` in `esm` format, `const { name } = require("specifier")` in `cjs`.
The string after `=` is the imported binding name.

```mbt check
///|
#module("node:fs")
extern "js" fn read_file_sync(path : String, encoding : String) -> String = "readFileSync"
```

## Wasm / Wasm-GC backends

### Host imports

`fn name(..) = "module" "name"` declares a Wasm import. The host supplies it in
the import object at instantiation time (`{ math: { cos: Math.cos } }`):

```mbt check
///|
fn host_cos(d : Double) -> Double = "math" "cos"
```

### Inline Wasm (`extern "wasm"`)

The body is a Wasm `func` in text format — do NOT provide a function name inside
the `(func ...)`:

```mbt check
///|
extern "wasm" fn wasm_identity(d : Double) -> Double =
  #|(func (param f64) (result f64) (local.get 0))
```

### Host runtime requirements

- `main` is exported as `_start`; `init` compiles to the Wasm `start` function.
- `println` and stdlib I/O need the host to provide `spectest.print_char` (one
  UTF-16 code unit per call) — avoid stdlib I/O for portable modules.
- Closures passed to the host require `moonbit:ffi`/`make_closure` (see Callbacks).

## Foreign types

`#external type T` declares an opaque host value — `externref` on wasm/wasm-gc,
`any` on js (and `void*` on C). MoonBit performs no GC/refcount operations on
these values. The attribute goes on its own line before `type`:

```mbt check
///|
#external
type JsObject

///|
extern "js" fn object_new() -> JsObject =
  #|() => ({})
```

## Type ABI mapping

Only the types below have a stable ABI. Anything else (structs, enums with
payload, `Option`, etc.) has an unstable representation — never pass them
across FFI; convert at the boundary.

| MoonBit type | js | wasm | wasm-gc |
|---|---|---|---|
| `Bool` | `boolean` | `i32` | `i32` |
| `Int` / `UInt` | `number` | `i32` | `i32` |
| `Int64` / `UInt64` | unstable | `i64` | `i64` |
| `Float` | `number` | `f32` | `f32` |
| `Double` | `number` | `f64` | `f64` |
| constant `enum` | `number` | `i32` | `i32` |
| `#external type T` | `any` | `externref` | `externref` |
| `FuncRef[T]` | `Function` | `funcref` | `funcref` |
| `String` | `string` | unstable | `externref` iff JS String Builtin on |
| `Bytes` / `FixedArray[Byte]` | `Uint8Array` | unstable | unstable |
| `FixedArray[T]` / `Array[T]` | `T[]` | unstable | unstable |

On js, strings/arrays cross the boundary directly — bind string-taking JS APIs
with MoonBit `String` freely. On wasm/wasm-gc, keep strings as host values
behind `#external` types with host accessor imports, or enable
`use-js-builtin-string` (wasm-gc + JS host only), or use linear memory (wasm).

## Callbacks

`FuncRef[T]` holds a **closed** function (captures nothing) — a plain JS
`Function` / Wasm `funcref`. Ordinary function values may capture state.

**js**: closures pass directly — nothing special needed.

```mbt check
///|
extern "js" fn set_timeout(f : () -> Unit, ms : Int) -> Unit =
  #|(f, ms) => setTimeout(f, ms)
```

**wasm / wasm-gc**: a closure parameter compiles to an import of
`moonbit:ffi` / `make_closure`. The host must do the partial application:

```mbt check
///|
fn host_on_event(f : (Int) -> Unit) -> Unit = "env" "on_event"
```

```javascript
const imports = {
  "moonbit:ffi": {
    make_closure: (funcref, closure) => funcref.bind(null, closure),
  },
  env: { on_event: (f) => { /* f is a callable host function */ } },
};
```

## Constant enums for host constants

Constant enums (no payloads) compile to a plain integer on every backend. Set
values with `= <int>`; an unspecified value is previous + 1 (first defaults to
0). Ideal for binding host flag/constant sets:

```mbt check
///|
pub enum SdlFlags {
  Timer = 0x1
  Audio = 0x10
  Video = 0x20
  Joystick // = 0x21
}
```

Passing `Video` to an extern emits the literal `32` — no wrapper object.

## Exporting to the host

Public top-level functions (not methods, not polymorphic) are exported via the
`link` config in `moon.pkg`; `"name:alias"` renames the export. The config only
affects the package that declares it.

```
options(
  link: {
    "js": {
      "exports": ["add", "fib:test"],
      "format": "esm",       // esm (default) | cjs | iife
    },
    "wasm": {
      "exports": ["add"],
      // "import-memory": { "module": "env", "name": "memory" },
      // "export-memory-name": "memory",
      // also: "heap-start-address" (wasm linear only), "memory-limits", "shared-memory"
    },
    "wasm-gc": {
      "exports": ["add"],
      // "use-js-builtin-string": true,     // MoonBit String == JS string
      // "imported-string-constants": "_",  // must match JS host config
    },
  },
)
```

`link: true` (no object) just marks a non-main package for linking. Output: a
standalone `.js` file (js) or `.wasm` module (wasm/wasm-gc).

## Lifetime

- **js / wasm-gc**: host GC is reused — no manual reference counting.
- **wasm** (linear): reference counted like the C backend. The owned calling
  convention applies (`$moonbit.incref` / `$moonbit.decref`, plus `#borrow` /
  `#owned` attributes); rules match `c-ownership.md`.

## Pitfalls

1. **Ungated FFI files break other targets.** `extern "js"` in a file compiled
   for wasm is an error. Always gate files with `targets` in `moon.pkg`.
2. **No polymorphic externs.** Monomorphize by hand (one extern per type).
3. **Unstable ABI types across wasm FFI.** `String`/`Bytes`/`Array` have no
   stable wasm representation — use `#external` handles or host accessors. Fine on js.
4. **Forgetting `make_closure`.** Instantiating a wasm module that passes
   closures to the host fails with a missing `moonbit:ffi.make_closure` import.
5. **Dead-code elimination.** Externs and pub functions unreachable from
   `exports` (or `main`) are dropped from the output — export your entry points.
6. **`FuncRef[T]` must be closed.** Passing a capturing lambda where `FuncRef`
   is expected is error E4151; use a plain function type to allow captures.

## See also

- `c.md` — native C backend FFI (stubs, ownership, finalizers, ASan)
- MoonBit docs: `language/ffi.md`, `toolchain/moon/package.md` (link options)
