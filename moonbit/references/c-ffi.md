# MoonBit C FFI Reference

Step-by-step workflow for binding any C library to MoonBit using native FFI.

**Use this reference when**:
- Adding `extern "c" fn` declarations for a C library
- Writing C stub files (`moonbit.h`, `MOONBIT_FFI_EXPORT`)
- Configuring `moon.pkg` / `moon.pkg.json` for native builds (`native-stub`, `link.native`)
- Choosing `#borrow` vs ownership transfer for FFI parameters
- Wrapping C handles with external objects and finalizers
- Implementing callback trampolines (closures or `FuncRef`)
- Converting strings between MoonBit (UTF-16) and C (UTF-8)
- Running AddressSanitizer to catch memory bugs

**Companion references:**
- `c-ffi-ownership.md` — detailed `#owned` / `#borrow` semantics, `moonbit_incref`/`decref` rules
- `c-ffi-callbacks.md` — callback trampolines (FuncRef, closures)
- `c-ffi-including-sources.md` — strategies for including C library sources
- `c-ffi-asan.md` — AddressSanitizer validation

## Type mapping

Map C types to MoonBit types before writing any declarations.

| C Type | MoonBit Type | Notes |
|---|---|---|
| `int`, `int32_t` | `Int` | 32-bit signed |
| `uint32_t` | `UInt` | 32-bit unsigned |
| `int64_t` | `Int64` | 64-bit signed |
| `uint64_t` | `UInt64` | 64-bit unsigned |
| `float` | `Float` | 32-bit float |
| `double` | `Double` | 64-bit float |
| `bool` | `Bool` | **ABI is** `int32_t`, **not C99** `_Bool` — see Bool pitfall below |
| `uint8_t`, `char` | `Byte` | Single byte |
| `void` | `Unit` | Return type only |
| `void *` (opaque, GC-managed) | `type Handle` (opaque) | External object with finalizer |
| `void *` (opaque, C-managed) | `#external pub type Handle` | No GC tracking; C manages lifetime |
| `const uint8_t *`, `uint8_t *` | `Bytes` or `FixedArray[Byte]` | Use `#borrow` if C doesn't store it |
| `const char *` (UTF-8 string) | `Bytes` | Null-terminated by runtime; pass directly to C |
| `struct *` (small, no cleanup) | `struct Foo(Bytes)` | Value-as-Bytes pattern |
| `struct *` (needs cleanup) | `type Foo` (opaque) | External object with finalizer |
| `int` (enum/flags) | `UInt`, `Int`, or constant `enum` | `enum Foo { A = 0; B = 1 }` maps to `int32_t` |
| callback function pointer | `FuncRef[...]` or closure | See `c-ffi-callbacks.md` |
| output `int *` | `Ref[Int]` | Borrow the Ref |

## Workflow

Follow these 4 phases in order.

### Phase 1: Project setup

Set up `moon.mod` and `moon.pkg` for native compilation.

**Module (`moon.mod`):** set `"preferred-target": "native"` so that `moon build`/`test`/`run` default to native:

```
options(
  "preferred-target": "native"
)
```

**Package (`moon.pkg`):**

```
options(
  "native-stub": ["stub.c"],
  targets: {
    "ffi.mbt": ["native"]
  },
)
```

**Key fields:**

| Field | Purpose |
|---|---|
| `"native-stub"` | C source files to compile. Must be in the same directory as `moon.pkg`. |
| `targets` | Gate `.mbt` files to backends: `"ffi.mbt": ["native"]` |
| `link(native("cc-flags": ...))` | Compile flags (`-I`, `-D`). Only for system libraries. |
| `link(native("cc-link-flags": ...))` | Linker flags (`-L`, `-l`). Only for system libraries. |
| `link(native("stub-cc-flags": ...))` | Compile flags for stub files only |
| `link(native(exports: ...))` | Export MoonBit functions to C (reverse direction) |

> **Warning — `supported_targets`:** Avoid package-wide `supported_targets = "native"` unless the whole package is native-only. Use `targets` to gate individual files when only the FFI file is native-specific.

> **Warning — `cc` / `cc-flags` portability:** Setting `cc` disables TCC for debug builds. Setting `cc-flags` with `-I` / `-L` breaks Windows portability. Only set these for system libraries.

**Including library sources**: all files in `"native-stub"` must be in the same directory as `moon.pkg`. For inclusion strategies (flattening, header-only, system library linking), see `c-ffi-including-sources.md`.

### Phase 2: FFI layer

Write extern declarations and C stubs together. Keep externs private; expose safe wrappers in Phase 3. Both `extern "c"` and `extern "C"` are valid — pick one and be consistent.

#### Critical — `Bool` ABI mismatch with C `bool`

MoonBit `Bool` uses `int32_t` (4 bytes) in the C ABI, but C99 `bool` / `_Bool` is typically 1 byte. **You cannot directly bind a C function that returns or accepts `bool` using MoonBit `Bool`.** Write a C stub that converts:

```c
// WRONG: direct passthrough to C bool function
//   extern "c" fn is_ready() -> Bool = "IsReady"
//   ^^^ IsReady() returns bool (_Bool, 1 byte), MoonBit reads int32_t — ABI mismatch

// CORRECT: stub wrapper that casts bool → int
MOONBIT_FFI_EXPORT
int32_t moonbit_is_ready(void) {
  return (int)IsReady();  // bool → int widens to int32_t
}
```

```mbt nocheck
extern "c" fn is_ready() -> Bool = "moonbit_is_ready"
```

Same for parameters — accept `int` in the stub, cast to `bool` when calling C:

```c
MOONBIT_FFI_EXPORT
unsigned int moonbit_load_depth(int w, int h, int use_rb) {
  return rlLoadTextureDepth(w, h, (bool)use_rb);  // int → bool
}
```

**Rule**: never bind directly to a C symbol that uses `bool` in its signature. Always interpose a stub.

#### External object pattern (C handle with cleanup, GC-managed)

```mbt nocheck
///|
type Parser  // opaque type backed by external object

///|
extern "c" fn ts_parser_new() -> Parser = "moonbit_ts_parser_new"

///|
#borrow(parser)
extern "c" fn ts_parser_language(parser : Parser) -> Language = "moonbit_ts_parser_language"
```

```c
// stub.c
#include "tree_sitter/api.h"
#include <moonbit.h>

typedef struct { TSParser *parser; } MoonBitTSParser;

static void moonbit_ts_parser_destroy(void *ptr) {
  ts_parser_delete(((MoonBitTSParser *)ptr)->parser);
  // Do NOT free ptr — GC manages the container
}

MOONBIT_FFI_EXPORT
MoonBitTSParser *moonbit_ts_parser_new(void) {
  MoonBitTSParser *p = (MoonBitTSParser *)moonbit_make_external_object(
    moonbit_ts_parser_destroy, sizeof(TSParser *)
  );
  p->parser = ts_parser_new();
  return p;
}
```

#### `#external` annotation (C pointer, C-managed lifetime)

When C fully manages the pointer's lifetime (no GC cleanup needed), annotate the type with `#external`. The pointer is passed as raw `void*` without reference counting:

```mbt nocheck
///|
#external
pub type RawPtr  // void*, not GC-tracked

///|
extern "c" fn raw_create() -> RawPtr = "lib_create"

///|
extern "c" fn raw_destroy(ptr : RawPtr) = "lib_destroy"
```

`#external` is an annotation (like `#borrow` and `#owned`) — it goes on its own line BEFORE the `type` declaration, not on the same line.

No C stub wrapper or `moonbit_make_external_object` needed — the extern calls the C function directly. Use this when the C API has explicit create/destroy and you want manual lifetime control, OR for **borrowed opaque pointers** (transfer="none"), like signal parameters or borrowed returns that you must not free.

#### Ownership annotations

| Annotation | When to use |
|---|---|
| `#borrow(param)` | C only reads during the call; does not store a reference |
| `#owned(param)` | Ownership transfers to C; C must `moonbit_decref` when done |

Rules:
- Annotate every non-primitive parameter as `#borrow` or `#owned`.
- Primitives (`Int`, `UInt`, `Bool`, `Double`, etc.) are passed by value — no annotation needed.
- If unsure whether C stores a reference, do NOT use `#borrow`.
- Use `Ref[T]` with `#borrow` for output parameters where C writes a value back.

See `c-ffi-ownership.md` for detailed semantics.

#### String conversion across FFI

MoonBit `Bytes` is null-terminated by the runtime, so it can be passed directly to C functions expecting `const char *`. For the reverse (C string → MoonBit), use `moonbit_make_bytes` + `memcpy`:

```c
// C side: return a C string as MoonBit Bytes
MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_get_name(void *handle) {
  const char *str = lib_get_name(handle);
  int32_t len = strlen(str);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, str, len);
  return bytes;  // if str was malloc'd, free(str) before returning
}
```

```mbt nocheck
// MoonBit side: decode UTF-8 Bytes to String
// Requires import "moonbitlang/core/encoding/utf8" in moon.pkg
///|
pub fn get_name(handle : Handle) -> String {
  @utf8.decode_lossy(get_name_ffi(handle))
}
```

#### Value-as-Bytes pattern (small struct, no cleanup)

```c
MOONBIT_FFI_EXPORT
void *moonbit_settings_new(void) {
  return moonbit_make_bytes(sizeof(settings_t), 0);
}
```

```mbt nocheck
///|
struct Settings(Bytes)  // backed by GC-managed Bytes, no finalizer
```

#### Nullable external object returns — use `Ref[T]` output pattern

**Never** use `T?` (nullable) as the return type of an `extern "c" fn` that returns a GC-managed external object. MoonBit's C ABI doesn't correctly map C `NULL` → `None` for external objects — you'll always get `None` even when the C side returns a valid pointer.

Use the `Ref[T]` output parameter pattern instead:

```c
// C side: writes into *out, returns error code
MOONBIT_FFI_EXPORT
int32_t moonbit_foo_new(MoonBitFoo **out, /* ... args ... */) {
  MoonBitFoo *f = /* construct or NULL */;
  if (!f) return -1;
  *out = f;
  return 0;
}
```

```mbt nocheck
///|
extern "c" fn foo_new_ffi(out : Ref[Foo], /* args */) -> Int

///|
pub fn Foo::new(/* args */) -> Foo? {
  let out = Ref::new(placeholder_ffi())    // placeholder_ffi() returns a valid-but-empty Foo
  let code = foo_new_ffi(out, /* args */)
  if code == 0 { Some(out.val) } else { None }
}
```

You need a `placeholder_ffi()` that returns a valid-but-empty external object for `Ref` initialization.

#### `moonbit.h` core API

| API | Purpose |
|---|---|
| `moonbit_make_external_object(finalizer, size)` | GC-tracked object with cleanup finalizer |
| `moonbit_make_bytes(len, init)` | GC-managed byte array (MoonBit `Bytes`) |
| `moonbit_incref(ptr)` | Prevent GC collection of C-held object |
| `moonbit_decref(ptr)` | Release C's reference (pair with incref) |
| `Moonbit_array_length(arr)` | Length of GC-managed array or Bytes |
| `MOONBIT_FFI_EXPORT` | Required macro on all exported functions |

For the full API, read `$MOON_HOME/lib/moonbit.h` (default `MOON_HOME` is `~/.moon`).

### Phase 3: MoonBit API

Build safe public wrappers over the raw externs.

**Type declarations:**

```mbt nocheck
///|
type Parser               // opaque, backed by external object (has finalizer)

///|
struct Settings(Bytes)    // value type, backed by GC-managed Bytes

///|
struct Node(Bytes)        // small value struct
```

**Safe constructors and methods:**

```mbt nocheck
///|
pub fn Parser::new() -> Parser {
  ts_parser_new()
}

///|
pub fn Parser::set_language(self : Parser, language : Language) -> Bool {
  ts_parser_set_language(self, language)
}
```

**Error mapping:**

```mbt nocheck
///|
pub fn result_from_status(status : Int) -> Unit raise {
  if status < 0 {
    raise MyLibError(status)
  }
}
```

For callback patterns (FuncRef, closures, trampolines), see `c-ffi-callbacks.md`.

### Phase 4: Testing

```bash
moon test --target native -v
```

Run with AddressSanitizer to catch memory bugs:

```bash
moon run --target native scripts/run-asan.mbtx -- \
  --repo-root <project-root> \
  --pkg moon.pkg \
  --pkg main/moon.pkg
```

The `run-asan.mbtx` and `run-asan.py` scripts live under the skill's `scripts/` directory. See `c-ffi-asan.md` for details.

## Decision table

| Situation | Pattern | Key action |
|---|---|---|
| C reads pointer only during call | `#borrow(param)` | No decref in C |
| C takes ownership of pointer | `#owned(param)` | C must `moonbit_decref` |
| C handle needs cleanup on GC | External object + finalizer | `moonbit_make_external_object` |
| C pointer, C manages lifetime | `#external` annotation on `type` | No GC tracking; call C destroy explicitly |
| Small C struct, no cleanup | Value-as-Bytes | `moonbit_make_bytes` + `struct Foo(Bytes)` |
| Borrowed opaque pointer (transfer="none") | `#external pub type Foo` | No finalizer, no RC overhead |
| C returns null on failure (external object) | `Ref[T]` output + error code | Avoid `T?` return — ABI broken |
| Callback with data parameter | FuncRef + Callback trick | See `c-ffi-callbacks.md` |
| Callback without data parameter | FuncRef only | See `c-ffi-callbacks.md` |
| C string (UTF-8) output | `Bytes` across FFI | `moonbit_make_bytes` + `memcpy` in C; `@utf8.decode_lossy` in MoonBit |
| C function uses `bool` in signature | Stub wrapper with `int` | Return `(int)c_func()` in C; accept `int`, cast `(bool)` when calling C |
| Output parameter (`int *result`) | `Ref[T]` with `#borrow` | C writes into Ref; MoonBit reads `.val` |

## Common pitfalls

1. **`#borrow` when C stores the pointer.** GC may collect the object while C holds a stale reference. Only borrow for call-scoped access.

2. **Forgetting `moonbit_decref` on owned parameters.** Every non-borrowed, non-primitive parameter transfers ownership to C. Missing decrefs leak memory.

3. **Calling `free()` on external object containers.** The GC manages the container. Finalizers must only release the inner C resource.

4. **Using `moonbit_make_bytes` for structs with inner pointers.** Bytes have no finalizer, so inner heap allocations leak. Use external objects instead.

5. **Missing `moonbit_incref` before callback invocation.** When C calls back into MoonBit, the GC may run. Incref MoonBit-managed objects before the call; decref after.

6. **Forgetting `MOONBIT_FFI_EXPORT`.** Without it, the function is invisible to the MoonBit linker.

7. **Binding directly to C functions that use `bool`.** MoonBit `Bool` is `int32_t` (4 bytes), but C99 `bool` / `_Bool` is 1 byte. Directly binding `extern "c" fn foo() -> Bool = "c_foo"` where `c_foo` returns `bool` causes an ABI mismatch — MoonBit reads 4 bytes from the return register but only 1 byte was set, leaving garbage in the upper bytes. **Always write a C stub** that returns `int` (cast via `(int)`) for Bool return values, and accepts `int` for Bool parameters. This applies to both return types and parameters.

8. **`extern "c" fn ... -> T?` for external objects.** The Option encoding doesn't match the raw pointer return. `None` is always returned. Use `Ref[T]` output pattern + error code instead.

## See also

- `c-ffi-ownership.md` — ownership semantics, `#owned`/`#borrow` rules, `moonbit_incref`/`decref` operations
- `c-ffi-callbacks.md` — FuncRef, closures, trampolines
- `c-ffi-including-sources.md` — C library source inclusion strategies
- `c-ffi-asan.md` — AddressSanitizer validation workflow

JS FFI follows similar principles (`extern "js"`) but is not covered here — see MoonBit's official documentation.
