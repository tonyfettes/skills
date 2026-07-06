This MoonBit project (native backend) binds a small vendor C library,
`label/label.c`, which is already wired into the build via `native-stub`.

Implement the two stub functions in `label/label.mbt` by binding the two C
functions (`label_len`, `buf_sum`) declared in `label/label.c`:

- `label_len_of(name : String) -> Int` — the byte length of `name`'s UTF-8
  representation, as measured by the C `label_len` (it must actually call the
  C function).
- `payload_sum(data : Bytes) -> Int` — the sum of all bytes of `data` via the
  C `buf_sum`. `data` is binary and may contain zero bytes anywhere.

Requirements:

- Do not modify `label/label.c` (the grader restores it).
- Keep the public signatures exactly as given.
- The project must pass `moon check --target native` when you are done. You
  may add tests of your own (run with `moon test --target native`).

Work only inside the current directory.
