// This class parses a PACKAGES.TXT file and returns the database of
// packages that it finds there, in addition to all installed packages.

#ifndef CPARSER_H
#define CPARSER_H

#include <iostream>
#include <map>

struct	Spackage_simple {
	std::string	name;	// Necessary to preserve capitalization
	std::string	mirror_version;
	std::string	installed_version;
	std::string	location;
	std::string	dependencies;
};

typedef	std::map<std::string, Spackage_simple>	package_map;

class CParser
{
public:
	CParser();
	package_map	Packages;
protected:
	std::string	get_package_name(const std::string& fromstr);
	std::string	get_package_version(const std::string& fromstr);
	std::string	ltrim(std::string str);
	bool		parse_file(const std::string& filename);
	void		parse_search(const std::string& directory);
	bool		case_compare();
};

#endif
