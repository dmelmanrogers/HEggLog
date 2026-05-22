#ifndef HEGGLOG_HASKELL2010_FFI_HELPERS_H
#define HEGGLOG_HASKELL2010_FFI_HELPERS_H

#include <stdint.h>

int64_t hegglog_ffi_add_i64(int64_t lhs, int64_t rhs);
void hegglog_ffi_reset(void);
int64_t hegglog_ffi_accum(int64_t value);
int64_t hegglog_ffi_current(void);
int64_t hegglog_ffi_bool_to_i64(uint8_t value);
int32_t hegglog_ffi_next_char(int32_t value);

#endif
