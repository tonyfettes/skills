///|
test "utf8 byte length via C strlen" {
  @debug.assert_eq(@label.label_len_of("hi"), 2)
  @debug.assert_eq(@label.label_len_of("中文"), 6)
  @debug.assert_eq(@label.label_len_of("héllo"), 6)
  @debug.assert_eq(@label.label_len_of("🚀"), 4)
}

///|
test "binary-safe sum with interior zero bytes" {
  @debug.assert_eq(@label.payload_sum(b"\x00\x01\x02\xff"), 258)
  @debug.assert_eq(@label.payload_sum(b"\x01\x00\x00\x00\x01"), 2)
  @debug.assert_eq(@label.payload_sum(b"\xff\xff"), 510)
}
