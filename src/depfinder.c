// vim:et:sta:sts=2:sw=2:ts=2:tw=79:

#include "depfinder.h"

/*
 * Returns the length of the package name from the full package name as it is
 * listed in /var/log/packages.
 * e.g. for "judy-1.0.5-x86_64-1" it will return 4.
 */
static uint8_t pkg_name_length(char *pkg_full_name) {
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
static char *pkg_name(char *full_pkg_name) {
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
static bool file_in_fhs(char *filename) {
  if (strncmp(filename, USRLIBDIR, strlen(USRLIBDIR)) == 0) return true;
  if (strncmp(filename, LIBDIR, strlen(LIBDIR)) == 0) return true;
  if (strncmp(filename, "usr/bin/", 8) == 0) return true;
  if (strncmp(filename, "usr/sbin/", 9) == 0) return true;
  if (strncmp(filename, "bin/", 4) == 0) return true;
  if (strncmp(filename, "sbin/", 5) == 0) return true;
  if (strncmp(filename, "usr/libexec/", 12) == 0) return true;
  return false;
}

/*
 * Adds an entry to the hashtable.
 */
static void add_ht_entry(reverse_log_t **revlog, const char *filename, const char *pkgname) {
  reverse_log_t *r = NULL; 
  HASH_FIND_STR(*revlog, filename, r);
  if (!r) {
    // new hash table entry
    r = malloc(sizeof(*r));
    r->filename = strdup(filename);
    r->packages = malloc(1*sizeof(char*));
    r->packages[0] = strdup(pkgname);
    r->count = 1;
    HASH_ADD_KEYPTR(hh, *revlog, r->filename, strlen(r->filename), r);
  } else {
    // hash table entry exists, just append to the packages list
    r->packages = realloc(r->packages, (r->count + 1)*sizeof(char*));
    r->packages[r->count] = strdup(pkgname);
    r->count++;
  }
}

/*
 * Reads the contents of a log file in /var/log/packages and for each file, it
 * adds an entry to the hashtable. The fhs option determines if it will only
 * look in FHS-specified directories.
 */
static void get_pkglog_contents(char *pkg_name, reverse_log_t **revlog, bool fhs) {
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
      char *filename = malloc(read + 1);
      if (filename == NULL) exit(EXIT_FAILURE);
      snprintf(filename, read + 1, "/%s", line);
      // populate reverse log hashtable here
      add_ht_entry(revlog, filename, pkg_name);
      free(filename);
    }
  } 
  fclose(fp);
  free(line);
  free(full_path);
}

/*
 * Parses a file path and removes any previous directory (..) from it.
 */
static void remove_dir_dots(char **path) {
  char *sub = NULL;
  // first remove all previous dir dots (..)
  while ((sub = strstr(*path, "/..")) != NULL) {
    // part1 is the substring before the "/.."
    size_t part1_len = (sub - *path) + 1;
    char *part1 = malloc(part1_len);
    snprintf(part1, part1_len, "%s", *path);
    // part2 is the substring after the "/.."
    size_t part2_len = strlen(sub) - 3;
    // now locate where the previous directory name is and remove it
    size_t n = strrchr(part1, '/') - part1; // number of initial chars to keep
    memmove(*path + n, sub + 3, strlen(sub) - 3 + 1);
    free(part1);
  }
  // then remove any current dir dot (.)
  while ((sub = strstr(*path, "/.")) != NULL) {
    size_t part1_len = (sub - *path);
    memmove(*path + part1_len, sub + 2, strlen(sub) - 2 + 1);
  }
}



/*
 * Opens the /var/log/packages directory and reads every log file in it, one by
 * one.
 */
void read_var_log_pkg(reverse_log_t **revlog, bool fhs) {
  DIR *dir;
  struct dirent *ent;
  if ((dir = opendir (VARLOGPKG)) == NULL) exit(EXIT_FAILURE);
  while ((ent = readdir (dir)) != NULL) {
    char *pkg_full_name = strdup(ent->d_name);
    char *pkg_short_name = pkg_name(pkg_full_name);
    if (pkg_short_name) {
      get_pkglog_contents(pkg_full_name, revlog, fhs);
    }
    free(pkg_short_name);
    free(pkg_full_name);
  }
  closedir (dir);
}

/* free the hash table contents */
void free_ht(reverse_log_t **rlog) {
  reverse_log_t *r, *tmp = NULL;
  HASH_ITER(hh, *rlog, r, tmp) {
    for (size_t i = 0; i < r->count; ++i) free(r->packages[i]);
    free(r->packages);
    free(r->filename);
    HASH_DEL(*rlog, r);
    free(r);
  }
}

/* free linked list */
void free_ll(ll_t **list) {
  ll_t *elt;
  ll_t *tmp;
  LL_FOREACH_SAFE(*list, elt, tmp) {
    free(elt->name);
    LL_DELETE(*list, elt);
    free(elt);
  }
}

/*
 * Runs ldd on the given executable filename and returns all libraries the
 * executable references in a linked list.
 */
uint8_t run_ldd(ll_t **lib_list, char *filename) {
  char *ldd = "/usr/bin/ldd";
  char *cmd = malloc(strlen(ldd) + strlen(filename) + 2);
  sprintf(cmd, "%s %s", ldd, filename);
  FILE *fp = popen(cmd, "r");
  if (fp == NULL) exit(EXIT_FAILURE);
  char *line = NULL;
  size_t len = 0;
  ssize_t read;
  while ((read = getline(&line, &len, fp)) != -1) {
    char *sub = strstr(line, "=> ");
    if (sub != NULL) {
      char *lib = NULL;
      lib = strtok(sub + 4, " (");
      remove_dir_dots(&lib);
      ll_t *new = malloc(sizeof(*new));
      if (new == NULL) exit(EXIT_FAILURE);
      new->name = strdup(lib);
      LL_APPEND(*lib_list, new);
    }
  }
  uint8_t res = pclose(fp);
  free(line);
  free(cmd);
  return res;
}
