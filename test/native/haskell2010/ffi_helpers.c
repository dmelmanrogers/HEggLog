#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

static int64_t hegglog_ffi_total = 0;
static int64_t hegglog_ffi_finalizer_total = 0;
static int64_t hegglog_ffi_finalizer_order = 0;
int64_t hegglog_ffi_global_i64 = 77;
int64_t hegglog_ffi_alt_i64 = 99;

int64_t hegglog_ffi_add_i64(int64_t lhs, int64_t rhs) {
  return lhs + rhs;
}

void hegglog_ffi_reset(void) {
  hegglog_ffi_total = 0;
}

int64_t hegglog_ffi_accum(int64_t value) {
  hegglog_ffi_total += value;
  return hegglog_ffi_total;
}

int64_t hegglog_ffi_current(void) {
  return hegglog_ffi_total;
}

int64_t hegglog_ffi_bool_to_i64(bool value) {
  return value ? 11 : 3;
}

int32_t hegglog_ffi_next_char(int32_t codepoint) {
  return codepoint + 1;
}

uint8_t hegglog_ffi_inc_u8(uint8_t value) {
  return (uint8_t)(value + 1);
}

int8_t hegglog_ffi_neg_i8(int8_t value) {
  return (int8_t)(-value);
}

uint64_t hegglog_ffi_id_u64(uint64_t value) {
  return value;
}

int64_t hegglog_ffi_read_i64_ptr(int64_t *ptr) {
  return *ptr;
}

void hegglog_ffi_write_i64_ptr(int64_t *ptr, int64_t value) {
  *ptr = value;
}

int64_t *hegglog_ffi_select_i64_ptr(bool use_alt) {
  return use_alt ? &hegglog_ffi_alt_i64 : &hegglog_ffi_global_i64;
}

int64_t hegglog_ffi_inc_i64(int64_t value) {
  return value + 1;
}

int64_t hegglog_ffi_apply_i64(int64_t (*fn)(int64_t), int64_t value) {
  return fn(value);
}

int64_t hegglog_ffi_apply_twice_i64(int64_t (*fn)(int64_t), int64_t value) {
  return fn(value) + fn(value + 1);
}

void hegglog_ffi_expect_i64(int64_t actual, int64_t expected) {
  if (actual != expected) {
    abort();
  }
}

void hegglog_ffi_reset_finalizers(void) {
  hegglog_ffi_finalizer_total = 0;
  hegglog_ffi_finalizer_order = 0;
}

void hegglog_ffi_count_i64_finalizer(int64_t *ptr) {
  hegglog_ffi_finalizer_total += *ptr;
}

void hegglog_ffi_count_i64_finalizer_one(int64_t *ptr) {
  hegglog_ffi_finalizer_total += *ptr;
  hegglog_ffi_finalizer_order = hegglog_ffi_finalizer_order * 10 + 1;
}

void hegglog_ffi_count_i64_finalizer_two(int64_t *ptr) {
  hegglog_ffi_finalizer_total += *ptr;
  hegglog_ffi_finalizer_order = hegglog_ffi_finalizer_order * 10 + 2;
}

int64_t hegglog_ffi_finalizer_total_value(void) {
  return hegglog_ffi_finalizer_total;
}

int64_t hegglog_ffi_finalizer_order_value(void) {
  return hegglog_ffi_finalizer_order;
}

double hegglog_ffi_double_const(void) {
  return 41.25;
}

float hegglog_ffi_float_const(void) {
  return 6.5f;
}

double hegglog_ffi_identity_double(double value) {
  return value;
}

float hegglog_ffi_identity_float(float value) {
  return value;
}

double hegglog_ffi_double_plus_one(double value) {
  return value + 1.0;
}

int64_t hegglog_ffi_score_double(double value) {
  return (int64_t)(value * 100.0 + (value >= 0.0 ? 0.5 : -0.5));
}

int64_t hegglog_ffi_score_float(float value) {
  return (int64_t)(value * 10.0f + (value >= 0.0f ? 0.5f : -0.5f));
}

int64_t hegglog_ffi_mix_float_double(float lhs, double rhs) {
  return hegglog_ffi_score_float(lhs) + hegglog_ffi_score_double(rhs);
}

int64_t hegglog_ffi_apply_double(double (*fn)(double), double value) {
  return hegglog_ffi_score_double(fn(value));
}
