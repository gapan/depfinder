// Author: George Vlahavas
// Well, not really, this is just a hack of zpm that is created by:
// Author: Nigel Bosch
// std::string Email = "sparkynigel" + "@" + "gmail" + ".com";
// See COPYING for license information.

#include <iostream>
#include <getopt.h>
#include <vector>
#include "defs.h"
#include "CWhatProvides.h"

#define SET_ACTION(action) _action = action

int main(int argc, char* argv[])
{
	std::vector<std::string>	_files;
	std::string			_arg_whatprovides;
	std::string			_shell_pid;

	_arg_whatprovides = argv[1];
	_shell_pid = argv[2];

	CWhatProvides	_ori(_arg_whatprovides, _shell_pid);
	return 0;
}
