#include <string>
#include <iostream>
#include <stdexcept>
#include <cstdlib>

#include "CommandHandler.hpp"
#include "SortHandler.hpp"
#include "MergeHandler2.hpp"
#include "Verifier.hpp"

void
printUsage(void)
{
    std::cerr
		<< "Usage: som command [options] [arguments]\n"
		<< "\n"
		<< "  Command: sort, merge, clip, unite, import, export, verify\n"
		<< "\n"
    	<< "  Please see help (-h) of each command for detail\n"
        ;
}

int
main(int argc, char* argv[])
{
	if (argc < 2){
		printUsage();
		exit(1);
	}

	std::string command = argv[1];

	std::vector<std::string> arguments(argv + 2, argv + argc);

	CommandHandler *handler;
    if (command == "sort") {
        handler = new SortHandler();
    }
	else if (command == "merge") {
        handler = new MergeHandler();
    }
	else if (command == "merge2") {
        handler = new MergeHandler2();
    }
	else if (command == "clip") {
        handler = new ClipOutHandler();
    }
	else if (command == "unite") {
        handler = new UniteHandler();
    }
	else if (command == "import") {
        handler = new ImportHandler();
    }
	else if (command == "export") {
        handler = new ExportHandler();
    }
	else if (command == "verify") {
        handler = new Verifier();
    }
    else {
		std::cerr << "som: unknown command: " << command << std::endl;
		printUsage();
		exit(1);
	}

    try {
        if (handler->exec(arguments)) {
	        return 0;
        }
        else {
            exit(1);
        }
    }
    catch (const std::runtime_error &e)
    {
        std::cerr << "som: error: " << e.what() << std::endl;
        exit(1);
    }

    /// Never reached
    return 0;
}

