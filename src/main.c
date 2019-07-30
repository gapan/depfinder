// vim:et:sta:sts=2:sw=2:ts=2:tw=79:

#include "depfinder.h"

int main(void) {
  reverse_log_t *rlog = NULL;
  read_var_log_pkg(&rlog, true); // set FHS=true for now
  
  ll_t *head = NULL;
  uint8_t res = run_ldd(&head, "/usr/bin/gimp");

  free_ht(&rlog);
  free_ll(&head);
  return 0;
}
