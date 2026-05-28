#include <stdint.h>

extern double hegglog_hs_export_double(double value);
extern float hegglog_hs_export_float(float value);

int64_t hegglog_ffi_score_export_double(double value) {
  double result = hegglog_hs_export_double(value);
  return (int64_t)(result * 100.0 + (result >= 0.0 ? 0.5 : -0.5));
}

int64_t hegglog_ffi_score_export_float(float value) {
  float result = hegglog_hs_export_float(value);
  return (int64_t)(result * 10.0f + (result >= 0.0f ? 0.5f : -0.5f));
}
