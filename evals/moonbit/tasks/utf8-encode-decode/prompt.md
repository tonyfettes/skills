This MoonBit project implements a small wire codec for a chat protocol.

Implement the two stub functions in `wire/wire.mbt`:

- `encode_message(msg : String) -> Bytes` — encode the message text as UTF-8 bytes.
- `decode_message(payload : Bytes) -> String raise` — decode a payload produced by `encode_message` back into the original text.

Requirements:

- Messages may contain any Unicode text (CJK, accents, emoji).
- A round trip `decode_message(encode_message(s)) == s` must hold for any valid string.
- Keep the public signatures exactly as given.
- The project must pass `moon check` when you are done. You may add tests of your own.

Work only inside the current directory.
