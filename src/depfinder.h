// vim:et:sta:sts=2:sw=2:ts=2:tw=79:

#ifndef DEPFINDER_H
#define DEPFINDER_H

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <dirent.h>
#include "uthash.h"
#include "utlist.h"

#if INTPTR_MAX == INT64_MAX
#define LIBDIR "lib64/"
#define USRLIBDIR "usr/lib64/"
#elif INTPTR_MAX == INT32_MAX
#define LIBDIR "lib/"
#define USRLIBDIR "usr/lib/"
#else
#error Unknown pointer size or missing size macros!
#endif

#ifndef EERROR
#define EERROR(s) {perror((s));exit(EXIT_FAILURE);}
#endif

#ifndef VARLOGPKG
#define VARLOGPKG "/var/log/packages"
#endif

#ifndef LDD_CMD
#define LDD_CMD "/usr/bin/ldd"
#endif

typedef struct {
  char *filename; // key
  uint16_t count;
  char **packages;
  UT_hash_handle hh; // makes this structure hashable
} reverse_log_t;

typedef struct ll_t {
  char *name;
  struct ll_t *next;
} ll_t;

/*
 * Opens the /var/log/packages directory and reads every log file in it, one by
 * one.
 */
void read_var_log_pkg(reverse_log_t **revlog, bool fhs);

/*
 * Runs ldd on the given executable filename and returns all libraries the
 * executable references in a linked list.
 */
uint8_t run_ldd(ll_t **lib_list, char *filename);

/* free the hash table contents */
void free_ht(reverse_log_t **rlog);

/* free linked list */
void free_ll(ll_t **list);

#endif // #ifdef DEPFINDER_H

