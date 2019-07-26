// vim:et:sta:sts=2:sw=2:ts=2:tw=79:

#include "depfinder.h"

int main(void) {
  reverse_log_t *rlog = NULL;
  read_var_log_pkg(&rlog, true); // set FHS=true for now
  
  free_ht(&rlog);
  return 0;
}
