#include <iostream>
#include <iterator>
#include <cassert>

#include "TagData.hpp"
#include "som_util.hpp"
#include "Verifier.hpp"

Verifier::Verifier(void)
{
    std::vector<std::string> options;
    options.push_back("-h");
    options.push_back("--help");

    std::vector<std::string> argumentOptions;
    argumentOptions.push_back("-t");
    
    optParser.setAllowedOptions(options, argumentOptions);
}

void
Verifier::printUsage(void)
{
    std::cerr
		<< "Usage: som verify [ -t tag_order_file ] <in_so>                  \n"
		<< "                                                                 \n"
    	<< "Use '-' as a file name to use standard input/output              \n"
		<< "                                                                 \n"
    	<< "Options:                                                         \n"
		<< "   -t file    : use 'file' as the tag-order file                 \n"
    	<< "   -h, --help : show this help                                   \n"
        ;
}

bool
Verifier::exec(const std::vector<std::string> &commandLineArgv)
{
    Options opts;
    std::vector<std::string> args;
    optParser.parseArgv(commandLineArgv, opts, args);

	///-------------------------------------------------------------------------
	/// Check options
	///-------------------------------------------------------------------------
	if (showHelp(opts)) {
		printUsage();
		return true;
	}

	if (args.size() != 1) {
		printUsage();
        return false;
	}

    StreamManager streamManager;

	std::vector<std::string> tagOrder;

	for (OptItr iter = opts.begin(); iter != opts.end(); ++iter) {

		if (iter->first == "-h" or iter->first == "--help"){
            /// Never reached
            assert(false);
		}
		else if (iter->first == "-t") {

            /// TODO: Add check for more than one '-t' options:
            ///   We now omit check for the case where more than one '-t'
            /// options are passed here (and also maybe in other commands);
            /// we append the tag-order lists in the order of their appearance
            /// in the command line, which would not be the expected behavior
            /// in most cases.

			std::istream *tagOrderFile
                = streamManager.getInputStream(iter->second);

			std::copy(
				std::istream_iterator<std::string>(*tagOrderFile),
				std::istream_iterator<std::string>(),
				std::back_inserter(tagOrder));
		}
		else {
            /// Never reached
            assert(false);
		}
	}

	///-------------------------------------------------------------------------
	/// Verify the well-formedness of the so file
	///-------------------------------------------------------------------------

    AIsLessThanB less(tagOrder);

    std::istream *soFile = streamManager.getInputStream(args[0]);
    TagStream tst(*soFile);

    TagData prevTag;
    TagData currTag;

    bool first = true;
    while (tst >> currTag) {

        if (first) {
            first = false;
        }
        else {
            if (less(currTag, prevTag)) {
                unsigned int lineNo = tst.getLineNumber();
                std::cerr << "som verify: Tag order inversion between line "
                    << (lineNo - 1) << " and " << lineNo << std::endl;
                return false;
            }
        }

        prevTag = currTag;
    }

    return true;
}
