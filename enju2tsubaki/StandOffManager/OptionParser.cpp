#include <stdexcept>

#include "OptionParser.hpp"

void OptionParser::setAllowedOptions(
	const std::vector<std::string> &options,
	const std::vector<std::string> &argumentOptions
) {
	allowedOpts.clear();
    allowedOpts.insert(options.begin(), options.end());

	allowedArgOpts.clear();
    allowedArgOpts.insert(argumentOptions.begin(), argumentOptions.end());
}

void
OptionParser::parseArgv(
    const std::vector<std::string> &argv,
    Options &options,
    std::vector<std::string> &arguments
) const {

	typedef std::vector<std::string>::const_iterator VItr;

	VItr iter = argv.begin();
    while (iter != argv.end()) {

		if (allowedOpts.find(*iter) != allowedOpts.end()) {

            /// Option without argument
			options.push_back(std::make_pair(*iter, ""));
		}
		else if (allowedArgOpts.find(*iter) != allowedArgOpts.end()) {

            /// Option without an argument
			std::string optName(*iter);

			++iter;

			if (iter == argv.end()) {
                throw std::runtime_error(
                    "option " + *iter + " requires an argument");
			}

			options.push_back(std::make_pair(optName, *iter));
		}
		else { /// Arguments for the command
			arguments.push_back(*iter);
		}

        ++iter;
	}
}

