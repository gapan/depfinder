// This class takes a list of files and determines which of the
// installed packages each file comes from, reading the package database
// only once.
// See COPYING for license information.

#ifndef CWHATPROVIDES_H
#define CWHATPROVIDES_H

#include <iostream>
#include <string>
#include <unordered_map>
#include <vector>

class CWhatProvides
{
public:
	CWhatProvides(const std::string& pkgdb, const std::string& pkglist,
		const std::string& filelist);
	// Prints a line for each file in the list, with the packages
	// providing it separated by "|", or empty if no package does
	void	print(std::ostream& out) const;
protected:
	void	search_package(const std::string& pkgdb, const std::string& package);
	void	add_provider(const std::string& path, const std::string& package);

	// The requested files, in order, and the packages providing each
	std::vector<std::string>			_files;
	std::vector<std::vector<std::string> >		_providers;
	// The path of each requested file, as recorded in the package
	// database, to its indexes in _files
	std::unordered_map<std::string, std::vector<size_t> >	_index;
};

#endif
