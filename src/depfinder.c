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
 * Returns the length of the package name from the full package name as it is
 * listed in /var/log/packages.
 * e.g. for "judy-1.0.5-x86_64-1" it will return 4.
 */
uint8_t pkg_name_length(char *pkg_full_name) {
  uint8_t l = strlen(pkg_full_name);
  uint8_t count_dashes = 0;
  for (uint8_t i = l; i > 0 ; --i) {
    char c = pkg_full_name[i];
    if (c == '-') ++count_dashes;
    if (count_dashes == 3) return i;
  }
  return 0;
}

/*
 * Returns the package name from the full package name as it is
 * listed in /var/log/packages.
 * e.g. for "judy-1.0.5-x86_64-1" it will return "judy".
 * For a filename that does not match a package's naming structure, it will
 * return NULL.
 */
char *pkg_name(char *full_pkg_name) {
  uint8_t len = pkg_name_length(full_pkg_name) + 1; // '\0'
  if (len == 1) return NULL;
  char *pkg_name = malloc(len);
  if (pkg_name == NULL) exit(EXIT_FAILURE); 
  snprintf(pkg_name, len, full_pkg_name);
  return pkg_name;
}

/*
 * Checks if the filename is in an FHS directory
 */
bool file_in_fhs(char *filename) {
  if (strncmp(filename, USRLIBDIR, strlen(USRLIBDIR)) == 0) return true;
  if (strncmp(filename, LIBDIR, strlen(LIBDIR)) == 0) return true;
  if (strncmp(filename, "usr/bin/", 8) == 0) return true;
  if (strncmp(filename, "usr/sbin/", 9) == 0) return true;
  if (strncmp(filename, "bin/", 4) == 0) return true;
  if (strncmp(filename, "sbin/", 5) == 0) return true;
  if (strncmp(filename, "usr/libexec/", 12) == 0) return true;
  return false;
}

void add_ht_entry(reverse_log_t **revlog, const char *filename, const char *pkgname) {
  reverse_log_t *r = NULL; 
  HASH_FIND_STR(*revlog, filename, r);
  if (!r) {
    // new hash table entry
    r = malloc(sizeof(*r));
    r->filename = malloc(strlen(filename) + 1);
    sprintf(r->filename, "%s", filename);
    r->packages = malloc(1*sizeof(char*));
    r->packages[0] = malloc(strlen(pkgname) + 1);
    sprintf(r->packages[0], "%s", pkgname);
    r->count = 1;
    HASH_ADD_KEYPTR(hh, *revlog, r->filename, strlen(r->filename), r);
  } else {
    // hash table entry exists, just append to the packages list
    r->packages = realloc(r->packages, (r->count + 1)*sizeof(char*));
    r->packages[r->count] = malloc(strlen(pkgname) + 1);
    sprintf(r->packages[r->count], "%s", pkgname);
    r->count++;
  }
}

void get_pkglog_contents(char *pkg_name, reverse_log_t **revlog, bool fhs) {
  size_t len = strlen(VARLOGPKG) + strlen(pkg_name) + 2;
  char *full_path = malloc(len);
  if (full_path == NULL) exit(EXIT_FAILURE);
  snprintf(full_path, len, "%s/%s", VARLOGPKG, pkg_name);
  FILE *fp = fopen(full_path, "r");
  if (fp == NULL) exit(EXIT_FAILURE);
  char *line = NULL;
  ssize_t read;
  len = 0; // oh well, repurpose this, it's not that we need the previous value
  bool start_reading = false;
  while ((read = getline(&line, &len, fp)) != -1) {
    if (strncmp(line, "FILE LIST:", 10) == 0) {
      start_reading = true;
      continue;
    }
    if (start_reading && (!fhs || file_in_fhs(line))) {
      // don't read directory entries, they're not useful in this context
      if (line[read - 2] == '/') continue; // last char is a newline char
      char *filename = malloc(read);
      if (filename == NULL) exit(EXIT_FAILURE);
      snprintf(filename, read, "%s", line);
      // populate reverse log hashtable here
      add_ht_entry(revlog, filename, pkg_name);
      free_zero(filename);
    }
  } 
  fclose(fp);
  free_zero(line);
  free_zero(full_path);
}

void read_var_log_pkg(reverse_log_t **revlog, bool fhs) {
  DIR *dir;
  struct dirent *ent;
  if ((dir = opendir (VARLOGPKG)) == NULL) exit(EXIT_FAILURE);
  while ((ent = readdir (dir)) != NULL) {
    char *pkg_full_name = malloc(strlen(ent->d_name) + 1);
    sprintf(pkg_full_name, "%s", ent->d_name);
    char *pkg_short_name = pkg_name(pkg_full_name);
    if (pkg_short_name) {
      get_pkglog_contents(pkg_full_name, revlog, fhs);
    }
    free_zero(pkg_short_name);
    free_zero(pkg_full_name);
  }
  closedir (dir);
}

int main(void) {
  reverse_log_t *rlog = NULL;
  reverse_log_t *r, *tmp = NULL;
  read_var_log_pkg(&rlog, true); // set FHS=true for now
  
  HASH_FIND_STR(rlog, "lib64/libcrypto.so.1.0.0", r);
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
