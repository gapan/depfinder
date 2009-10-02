// See COPYING for license information.

// Defines to be used for loading file names.
#ifndef TMPDIR
#define TMPDIR		"/tmp/depfinder."
#endif
#ifndef TMPFILE
#define TMPFILE(file,shellpid)	std::string(TMPDIR + std::string(shellpid) + std::string(file) )
#endif
