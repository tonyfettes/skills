///|
#borrow(s)
extern "c" fn label_len(s : Bytes) -> Int = "label_len"

///|
#borrow(p)
extern "c" fn buf_sum(p : Bytes, n : Int) -> Int = "buf_sum"

///|
/// Byte length of `name`'s UTF-8 representation, as measured by the vendor
/// C library's `label_len` (see label.c). Must go through the C function.
pub fn label_len_of(name : String) -> Int {
  // Bytes is NUL-terminated by the runtime — pass directly as const char *.
  label_len(@utf8.encode(name))
}

///|
/// Sum of all bytes in `data` (binary-safe — `data` may contain zero
/// bytes anywhere), via the vendor C library's `buf_sum`.
pub fn payload_sum(data : Bytes) -> Int {
  buf_sum(data, data.length())
}
