This MoonBit project is the storage layer of an async network service built on `moonbitlang/async` (already a dependency; the whole program runs inside the async runtime on the native backend).

Implement the three stub functions in `store/store.mbt`:

- `save_blob(path : String, data : Bytes) -> Unit` — write `data` to the file at `path`, overwriting any existing file.
- `load_blob(path : String) -> Bytes` — read back the file contents.
- `has_blob(path : String) -> Bool` — whether a blob exists at `path`.

Requirements:

- Data is binary (may contain zero bytes) and must round-trip exactly.
- Keep the public signatures exactly as given (they are `async fn` — the callers run inside the async runtime and must not block the event loop).
- The project must pass `moon check --target native` when you are done. You may add tests of your own.

Work only inside the current directory.
