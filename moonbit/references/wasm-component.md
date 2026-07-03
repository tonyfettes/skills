# Wasm Component Model

Building WebAssembly components from MoonBit: define interfaces in WIT,
generate bindings with `wit-bindgen moonbit`, package with `wasm-tools`, test
with `wasmtime`. Use this when a MoonBit module must interop with component
hosts (wasmtime, jco, Spin, …) rather than plain wasm FFI (`ffi-js-wasm.md`
covers custom import/export).

Tool versions evolve; generated layout and flags below follow the official
tutorial (wit-bindgen 0.45) — verify against `wit-bindgen moonbit --help` on
the installed version.

## Prerequisites

```sh
cargo install wit-bindgen-cli   # generates MoonBit bindings from WIT
cargo install wasm-tools        # componentize / inspect wasm
# wasmtime for running: https://wasmtime.dev/
```

## 1. Define the interface (WIT)

`wit/world.wit`:

```wit
package docs:adder@0.1.0;

interface add {
    add: func(x: u32, y: u32) -> u32;
}

world adder {
    export add;
}
```

## 2. Generate the MoonBit project

```sh
wit-bindgen moonbit wit/world.wit --out-dir . \
    --derive-eq --derive-show --derive-error
```

| Flag | Effect |
|---|---|
| `--derive-eq` / `--derive-show` | add `derive(Eq)` / `derive(Show)` to all generated types |
| `--derive-error` | WIT variants/enums with "Error" in the name become MoonBit `suberror`s, so `raise`/`catch` integrate naturally |
| `--ignore-stub` | regenerate bindings after a WIT change WITHOUT touching your `stub.mbt` implementations |
| `--project-name <name>` | override the module name (useful when embedding into a larger project) |
| `--gen-dir <dir>` | export bindings go somewhere other than the default `gen/` |
| `--out-dir <dir>` | root output directory |

Generated layout: `moon.mod.json` at root; `gen/` holds export bindings —
implement your logic in `gen/interface/<pkg-path>/stub.mbt` (bodies are the
`...` placeholder, which `moon check --target wasm` flags as unfinished code);
`world/` (top level) holds import bindings; `ffi/` is low-level glue. Newer
wit-bindgen may emit `moon.pkg` instead of `moon.pkg.json`.

## 3. Implement, build, componentize

Fill in the stub:

```mbt nocheck
///|
pub fn add(x : UInt, y : UInt) -> UInt {
  x + y
}
```

```sh
moon build --target wasm

# core module -> component: embed the WIT metadata, then lift
wasm-tools component embed wit _build/wasm/release/build/gen/gen.wasm \
    --encoding utf16 \
    --output adder.wasm
wasm-tools component new adder.wasm --output adder.component.wasm

# inspect the component's interface
wasm-tools component wit adder.component.wasm
```

Notes:
- `--encoding utf16` matters — MoonBit strings are UTF-16.
- Older moon puts the artifact under `target/wasm/release/build/...` instead
  of `_build/...`.

## 4. Test with wasmtime

```sh
wasmtime run --invoke 'add(10, 20)' adder.component.wasm
# 30
```

Or use a host program (e.g. the bytecodealliance `component-docs`
`example-host`) to load the component from Rust.

## Q&A: `spectest.print_char` import

Plain-wasm output may import `spectest.print_char` — that's how MoonBit prints
(one UTF-16 code unit at a time). For portable/component output, avoid
`println`; if the import still appears in the final binary, eliminate it with
[`wasm-merge`](https://github.com/WebAssembly/binaryen) or similar tools.
