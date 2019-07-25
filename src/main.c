// vim:et:sta:sts=2:sw=2:ts=2:tw=79:

#include "depfinder.h"

int main(void) {
  reverse_log_t *rlog = NULL;
  reverse_log_t *r, *tmp = NULL;
  read_var_log_pkg(&rlog, true); // set FHS=true for now
  
  HASH_FIND_STR(rlog, "lib64/libcrypto.so.1.0.0", r);
  if (r) {
    for (int i = 0; i < r->count; ++i) printf("%s\n", r->packages[i]);
  }
  HASH_FIND_STR(rlog, "usr/lib64/libusb-1.0.so.0.1.0", r);
  if (r) {
    for (int i = 0; i < r->count; ++i) printf("%s\n", r->packages[i]);
  }

  /* free the hash table contents */
  HASH_ITER(hh, rlog, r, tmp) {
    for (size_t i = 0; i < r->count; ++i) free_zero(r->packages[i]);
    free_zero(r->packages);
    free_zero(r->filename);
    HASH_DEL(rlog, r);
    free(r);
  }
  
  return 0;
}
