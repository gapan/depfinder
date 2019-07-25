// vim:et:sta:sts=2:sw=2:ts=2:tw=79:
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <dirent.h>
#include "uthash.h"

#if INTPTR_MAX == INT64_MAX
#define LIBDIR "lib64/"
#define USRLIBDIR "usr/lib64/"
#elif INTPTR_MAX == INT32_MAX
#define LIBDIR "lib/"
#define USRLIBDIR "usr/lib/"
#else
#error Unknown pointer size or missing size macros!
#endif

#define free_zero(p) {free(p); p = 0;}
#define VARLOGPKG "/var/log/packages"

typedef struct {
  char *filename; // key
  uint16_t count;
  char **packages;
  UT_hash_handle hh; // makes this structure hashable
} reverse_log_t;

/*
 * Opens the /var/log/packages directory and reads every log file in it, one by
 * one.
 */
void read_var_log_pkg(reverse_log_t **revlog, bool fhs);
