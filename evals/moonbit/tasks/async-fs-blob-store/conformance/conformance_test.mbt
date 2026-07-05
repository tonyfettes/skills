///|
async test "binary blob roundtrip with zero bytes" {
  let path = "conformance_blob_a.bin"
  let data : Bytes = b"\x00\x01\x02hello\xff\x00world\x80"
  @store.save_blob(path, data)
  assert_true(@store.has_blob(path))
  let back = @store.load_blob(path)
  @debug.assert_eq(back, data)
}

///|
async test "save overwrites existing blob" {
  let path = "conformance_blob_b.bin"
  @store.save_blob(path, b"first version, quite long payload")
  @store.save_blob(path, b"v2")
  @debug.assert_eq(@store.load_blob(path), b"v2")
}

///|
async test "has_blob false for missing path" {
  assert_true(!(@store.has_blob("conformance_no_such_file.bin")))
}
