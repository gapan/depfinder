// This class takes a file name and attempts to determine which package
// or packages that file could have come from, out of the packages which
// have been installed.
// See COPYING for license information.

#ifndef CWHATPROVIDES_H
#define CWHATPROVIDES_H

#include <iostream>

class CWhatProvides
{
public:
	CWhatProvides(std::string& file, std::string& shellpid);
protected:
	void	search_package(const std::string& package, const std::string& file);
};

#endif
