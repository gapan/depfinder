// See COPYING for license information.

#include <fstream>
#include <algorithm>
#include <climits>
#include <cstdlib>
#include <sys/stat.h>
#include "CWhatProvides.h"

// The path of a file as it appears in a package's file list: without the
// leading "/", and if the file is a symlink, the file it points to, since
// symlinks usually aren't in the file list (makepkg puts them in
// doinst.sh).
static std::string record_path(const std::string& file)
{
	std::string	path = file[0] == '/' ? file : "/" + file;
	struct stat	st;
	char		resolved[PATH_MAX];

	if ( lstat(path.c_str(), &st) == 0 && S_ISLNK(st.st_mode) &&
	     realpath(path.c_str(), resolved) != NULL )
		path = resolved;
	size_t		start = path.find_first_not_of('/');

	return start == std::string::npos ? "" : path.substr(start);
}

CWhatProvides::CWhatProvides(const std::string& pkgdb,
	const std::string& pkglist, const std::string& filelist)
{
	std::ifstream	_in;
	std::string	_line;

	_in.open(filelist.c_str(), std::ios_base::in);
	while ( getline(_in, _line) ) {
		if ( !_line.empty() )
			_index[record_path(_line)].push_back(_files.size());
		_files.push_back(_line);
	}
	_in.close();
	_providers.resize(_files.size());
	if ( _files.empty() )
		return;

	// Go through all installed packages, once.
	_in.open(pkglist.c_str(), std::ios_base::in);
	while ( getline(_in, _line) ) {
		if ( !_line.empty() )
			search_package(pkgdb, _line);
	}
	_in.close();
}

void CWhatProvides::search_package(const std::string& pkgdb, const std::string& package)
{	// Look up every line of the package's file list.
	std::ifstream	_ifpkg((pkgdb + "/" + package).c_str(), std::ios_base::in);
	std::string	_instr;
	bool		_file_list = false;

	while ( getline(_ifpkg, _instr) ) {
		if ( _file_list ) {
			add_provider(_instr, package);
			// Some packages (glibc, aaa_glibc-solibs) have files
			// in an "incoming" directory, which doinst.sh moves
			// to the directory above, e.g. lib64/incoming/libc-2.33.so
			// is installed as lib64/libc-2.33.so
			size_t _incoming = _instr.find("/incoming/");
			if ( _incoming != std::string::npos )
				add_provider(_instr.erase(_incoming, 9), package);
		} else {
			std::transform(_instr.begin(), _instr.end(), _instr.begin(), ::tolower);
			if ( _instr.compare(0, 10, "file list:") == 0 )
				_file_list = true;
		}
	}
}

void CWhatProvides::add_provider(const std::string& path, const std::string& package)
{	// If path is one of the requested files, package provides it.
	auto _found = _index.find(path);
	if ( _found == _index.end() )
		return;
	for ( size_t i : _found->second ) {
		std::vector<std::string>& p = _providers[i];
		if ( p.empty() || p.back() != package )
			p.push_back(package);
	}
}

void CWhatProvides::print(std::ostream& out) const
{
	for ( const std::vector<std::string>& p : _providers ) {
		for ( size_t i = 0; i < p.size(); i++ )
			out << (i ? "|" : "") << p[i];
		out << "\n";
	}
}
