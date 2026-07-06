// Vendor C library, pre-wired for MoonBit native linking.
// DO NOT MODIFY THIS FILE — the grader restores it before running.

#include <stdint.h>
#include <string.h>
#include <moonbit.h>

// Byte length of a NUL-terminated C string.
MOONBIT_FFI_EXPORT
int32_t label_len(const char *label) {
  return (int32_t)strlen(label);
}

// Sum of the first n bytes of p (binary-safe).
MOONBIT_FFI_EXPORT
int32_t buf_sum(const uint8_t *p, int32_t n) {
  int32_t s = 0;
  for (int32_t i = 0; i < n; i++) {
    s += p[i];
  }
  return s;
}
