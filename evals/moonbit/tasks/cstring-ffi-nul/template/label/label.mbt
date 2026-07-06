///|
/// Byte length of `name`'s UTF-8 representation, as measured by the vendor
/// C library's `label_len` (see label.c). Must go through the C function.
pub fn label_len_of(name : String) -> Int {
  ...
}

///|
/// Sum of all bytes in `data` (binary-safe — `data` may contain zero
/// bytes anywhere), via the vendor C library's `buf_sum`.
pub fn payload_sum(data : Bytes) -> Int {
  ...
}
