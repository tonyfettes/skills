///|
test "exact utf8 bytes for multibyte text" {
  // "中文 OK" in UTF-8: e4 b8 ad  e6 96 87  20  4f 4b
  let b = @wire.encode_message("中文 OK")
  assert_true(b is [0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87, 0x20, 0x4f, 0x4b])
}

///|
test "ascii stays ascii" {
  let b = @wire.encode_message("hello")
  assert_true(b is [0x68, 0x65, 0x6c, 0x6c, 0x6f])
}

///|
test "roundtrip cjk accents emoji" {
  for s in ["中文消息", "héllo wörld", "🚀 rocket 🌙", "mixed 中英 café 🎉"] {
    @debug.assert_eq(@wire.decode_message(@wire.encode_message(s)), s)
  }
}

///|
test "decode known utf8 bytes" {
  // "日本語" in UTF-8
  let payload : Bytes = b"\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e"
  @debug.assert_eq(@wire.decode_message(payload), "日本語")
}
