// See COPYING for license information.

#include <fstream>
#include <algorithm>
#include "defs.h"
#include "CWhatProvides.h"

CWhatProvides::CWhatProvides(std::string& file, std::string& shellpid)
{
	// Mangle the request to be more easily seachable.
	if ( file.find(".new") == file.length() - 1 && (int)file.find(".new") != -1 )
		file.erase(file.length() - 4);

	// Go through all installed packages.
	std::ifstream	_logfile;
	std::string	_inputstr;
	_logfile.open(TMPFILE("/pkglist.log", shellpid).c_str(), std::ios_base::in);
	while ( !_logfile.eof() ) {
		getline(_logfile, _inputstr);
		if ( _inputstr.length() > 0 ) search_package("/var/lib/pkgtools/packages/" + _inputstr, file);
	}
	_logfile.close();
}

void CWhatProvides::search_package(const std::string& package, const std::string& file)
{	// Search a specific package for the requested file.
	std::ifstream	_ifpkg;
	std::string	_instr;
	bool		_file_list = false;
	_ifpkg.open(package.c_str(), std::ios_base::in);

	while ( _ifpkg.is_open() && !_ifpkg.eof() ) {
		getline(_ifpkg, _instr);
		std::string	_original_fname = _instr;
		
		if ( _file_list ) {
			_instr = "/" + _instr;
			if ( (int)_instr.find(file) != -1 )
				std::cout << package.substr((int)package.rfind('/') + 1) << "\n";
		} else {
			std::transform(_instr.begin(), _instr.end(), _instr.begin(), tolower);
			if ( !_instr.find("file list:") ) {
				_file_list = true;
			}
		}
	}
}
