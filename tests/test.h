// vim:et:sta:sts=2:sw=2:ts=2:tw=79:

#include <check.h>

/*
 * Look in a mockup package log directory, instead of the official one
 */
#ifndef VARLOGPKG
#define VARLOGPKG "var_log_packages"
#endif

#include "../src/depfinder.c"
