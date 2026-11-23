// Author: George Vlahavas
// Well, not really, this is just a hack of zpm that is created by:
// Author: Nigel Bosch
// std::string Email = "sparkynigel" + "@" + "gmail" + ".com";
// See COPYING for license information.

#include <iostream>
#include "CWhatProvides.h"

int main(int argc, char* argv[])
{
	if ( argc != 4 ) {
		std::cerr << "usage: depfinder-search <package-db-dir> <package-list> <file-list>\n"
			"Prints, for each file in <file-list> (one per line) that an installed\n"
			"package provides, a line with the providing packages separated by \"|\".\n"
			"<package-list> names the package records in <package-db-dir> to read.\n";
		return 1;
	}

	std::ios_base::sync_with_stdio(false);
	CWhatProvides	_ori(argv[1], argv[2], argv[3]);
	_ori.print(std::cout);
	return 0;
}
