#include <stdint.h>

extern int64_t hegglog_hs_export_add(int64_t lhs, int64_t rhs);
extern int64_t hegglog_hs_export_io(int64_t value);

int64_t hegglog_ffi_call_export_add(int64_t lhs, int64_t rhs) {
  return hegglog_hs_export_add(lhs, rhs);
}

int64_t hegglog_ffi_call_export_io(int64_t value) {
  return hegglog_hs_export_io(value);
}
