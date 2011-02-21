#include <iostream>
#include <fstream>
#include <vector>
#include <cstdlib>
#include <cassert>
#include "CommandHandler.hpp"
#include "SortHandler.hpp"
#include "StandOffManager.hpp"
#include "som_util.hpp"

//------------------------------------------------------------------------------
// Sort Handler
//------------------------------------------------------------------------------

SortHandler::SortHandler(void)
{
    std::vector<std::string> opts;
    opts.push_back("-h");
    opts.push_back("--help");

    std::vector<std::string> argOpts;
    argOpts.push_back("-t");

    optParser.setAllowedOptions(opts, argOpts);
}

void
SortHandler::printUsage(void)
{
    std::cerr
		<< "Usage: som sort [-t tag_order_file] <input_so> <output_so>       \n"
		<< "                                                                 \n"
    	<< "Use '-' as the file name to use standard input/output            \n"
		<< "                                                                 \n"
    	<< "Options:                                                         \n"
		<< "   -t file    : use 'file' as the tag-order file                 \n"
    	<< "   -h, --help : show this help                                   \n"
        ;
}

bool
SortHandler::exec(const std::vector<std::string> &commandLineArgv)
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

	if (args.size() != 2) {
		printUsage();
        return false;
	}

    StreamManager streamManager;

	StandOffManager som;

	for (OptItr it = opts.begin(); it != opts.end(); ++it) {

		if (it->first== "-h" || it->first == "--help") {
			/// never reached
            assert(false);
		}
		else if (it->first == "-t") {
            som.readTagOrder(*streamManager.getInputStream(it->second));
		}
		else {
			/// never reached
            assert(false);
		}
	}

	///-------------------------------------------------------------------------
	/// Read data & sort
	///-------------------------------------------------------------------------
	std::istream *soIn = streamManager.getInputStream(args[0]);
	std::ostream *out  = streamManager.getOutputStream(args[1]);

	std::cerr << "Reading from " << args[0] << " .. " << std::endl;
    som.readData(*soIn);
	std::cerr << "done (" << som.getNumTags() << " tags)" << std::endl;

	std::cerr << "Sorting the tags .. ";
	som.sort();
	std::cerr << "done" << std::endl;

	som.writeData(*out);

    return true;
}

//------------------------------------------------------------------------------
// Merge Handler
//------------------------------------------------------------------------------
MergeHandler::MergeHandler(void)
{
    std::vector<std::string> opts;
    opts.push_back("-h");
    opts.push_back("--help");
    opts.push_back("-s");
    opts.push_back("-i");

    std::vector<std::string> argOpts;
    argOpts.push_back("-t");

    optParser.setAllowedOptions(opts, argOpts);
}

void
MergeHandler::printUsage(void)
{
    std::cerr
		<< "Usage: som merge [options] <input_so1> <input_so2> <output_so>   \n"
		<< "                                                                 \n"
    	<< "Use '-' as the file name to use standard input/output            \n"
		<< "                                                                 \n"
    	<< "Options:                                                         \n"
		<< "   -t file : use 'file' as the tag-order file                    \n"
    	<< "   -i      : don't check the well-formedness of the input files  \n"
    	<< "   -s      : merge with sorting (-i is implied)                  \n"
    	<< "   -h, --help : show this help                                   \n"
        ;
}

bool
MergeHandler::exec(const std::vector<std::string> &commandLineArgv)
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

	if (args.size() != 3) {
		printUsage();
        return false;
	}

    StreamManager streamManager;
	StandOffManager som1, som2;

	bool ignoreCheck = false;
	bool sortFlag = false;

	for (OptItr iter = opts.begin(); iter != opts.end(); ++iter) {

		if (iter->first == "-h" or iter->first == "--help"){
			/// never reached
            assert(false);
		}
		else if (iter->first == "-t") {
            som1.readTagOrder(*streamManager.getInputStream(iter->second));
		}
		else if (iter->first == "-i") {
			ignoreCheck = true;
		}
		else if (iter->first == "-s") {
			ignoreCheck = true;
			sortFlag = true;
		}
		else {
			/// never reached
            assert(false);
		}
	}

	///-------------------------------------------------------------------------
	/// Read data & exec merge
	///-------------------------------------------------------------------------
	std::istream *soIn1 = streamManager.getInputStream(args[0]);
	std::istream *soIn2 = streamManager.getInputStream(args[1]);
	std::ostream *out   = streamManager.getOutputStream(args[2]);

    std::cerr << "Reading from " << args[0] << " .. ";
    if (ignoreCheck) {
        som1.readData(*soIn1);
    }
    else {
        som1.readDataStrictly(*soIn1);
    }
	std::cerr << "done (" << som1.getNumTags() << " tags)" << std::endl;

    std::cerr << "Reading from " << args[1] << " .. ";
    if (ignoreCheck) {
        som2.readData(*soIn2);
    }
    else {
        som2.readDataStrictly(*soIn2);
    }
	std::cerr << "done (" << som2.getNumTags() << " tags)" << std::endl;

    std::cerr << "Merging .. ";
	som1 += som2;
    std::cerr << "done" << std::endl;

	if (sortFlag) {
        std::cerr << "Sorting .. ";
		som1.sort();
        std::cerr << "done" << std::endl;
	}

    std::cerr << "Wrting to " << args[2] << " .. " << std::endl;
	som1.writeData(*out);
    std::cerr << "done" << std::endl;

    return true;
}

//------------------------------------------------------------------------------
// Clip-Out Handler
//------------------------------------------------------------------------------

ClipOutHandler::ClipOutHandler(void)
{
    std::vector<std::string> opts;
    opts.push_back("-h");
    opts.push_back("--help");

    optParser.setAllowedOptions(opts, std::vector<std::string>());
}

void
ClipOutHandler::printUsage(void)
{
    std::cerr
		<< "Usage: som clip <in_so> <in_txt> <tag_file> <out_so> <out_txt>   \n"
		<< "                                                                 \n"
    	<< "Use '-' as the file name to use standard input/output            \n"
		<< "                                                                 \n"
    	<< "Options:                                                         \n"
    	<< "   -h, --help : show this help                                   \n"
        ;
}

bool
ClipOutHandler::exec(const std::vector<std::string> &commandLineArgv)
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

	if (args.size() != 5) {
		printUsage();
        return false;
	}

	///-------------------------------------------------------------------------
	/// Read data & exec clip
	///-------------------------------------------------------------------------
    StreamManager streamManager;

	std::istream *soIn   = streamManager.getInputStream(args[0]);
	std::istream *txtIn  = streamManager.getInputStream(args[1]);
	std::istream *tagIn  = streamManager.getInputStream(args[2]);

	std::ostream *soOut  = streamManager.getOutputStream(args[3]);
	std::ostream *txtOut = streamManager.getOutputStream(args[4]);

	StandOffManager som;

    som.clipData(*soIn, *txtIn, *tagIn, *soOut, *txtOut);

    return true;
}

//------------------------------------------------------------------------------
// Unite Handler
//------------------------------------------------------------------------------
UniteHandler::UniteHandler(void)
{
    std::vector<std::string> opts;
    opts.push_back("-h");
    opts.push_back("--help");

    optParser.setAllowedOptions(opts, std::vector<std::string>());
}

void
UniteHandler::printUsage(void)
{
    std::cerr
		<< "Usage: som unite [options] <container_so> <embedded_so> <out_so> \n"
		<< "                                                                 \n"
    	<< "Use '-' as a file name to use standard input/output              \n"
		<< "                                                                 \n"
    	<< "Option:                                                          \n"
		<< "   -t file    : use 'file' as the tag-order file                 \n"
    	<< "   -h, --help : show this help                                   \n"
        ;
}

bool
UniteHandler::exec(const std::vector<std::string> &commandLineArgv)
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

	if (args.size() != 3) {
		printUsage();
        return false;
	}

  StreamManager streamManager;
	StandOffManager som;

	for (OptItr iter = opts.begin(); iter != opts.end(); ++iter) {

		if (iter->first == "-h" || iter->first == "--help") {
			/// never reached
            assert(false);
		}
		else if (iter->first == "-t") {
            som.readTagOrder(*streamManager.getInputStream(iter->second));
		}
		else {
			/// never reached
            assert(false);
		}
	}

	///-------------------------------------------------------------------------
	/// Read data & exec unite
	///-------------------------------------------------------------------------
	std::istream *isSoffStrict  = streamManager.getInputStream(args[0]);
	std::istream *isSoffPartial = streamManager.getInputStream(args[1]);

	std::ostream *out = streamManager.getOutputStream(args[2]);

    //som.readConformedPositions(*isSoffStrict, *isSoffPartial);
    //som.writeData(*out);
    som.readConformedPositions(*isSoffStrict, *isSoffPartial, *out);

    return true;
}

//------------------------------------------------------------------------------
// Import Handler
//------------------------------------------------------------------------------
ImportHandler::ImportHandler(void)
{
    std::vector<std::string> opts;
    opts.push_back("-h");
    opts.push_back("--help");

    optParser.setAllowedOptions(opts, std::vector<std::string>());
}

void
ImportHandler::printUsage(void)
{
    std::cerr
		<< "Usage: som import [options] <input_semi_xml> <out_so> <out_txt>  \n"
		<< "                                                                 \n"
    	<< "Use '-' as file name(s) to use standard input/output             \n"
		<< "                                                                 \n"
    	<< "Options:                                                         \n"
    	<< "   -h, --help: show this help\n"
        ;
}

bool
ImportHandler::exec(const std::vector<std::string> &commandLineArgv)
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

	if (args.size() != 3) {
		printUsage();
        return false;
	}

	///-------------------------------------------------------------------------
	/// Read data & import
	///-------------------------------------------------------------------------
    StreamManager streamManager;

	std::istream *xmlIn  = streamManager.getInputStream(args[0]);
	std::ostream *soOut  = streamManager.getOutputStream(args[1]);
	std::ostream *txtOut = streamManager.getOutputStream(args[2]);

	StandOffManager som;

    /// TODO: error check in readSemiXMLandWriteRawText
    std::cerr << "Reading from " << args[0] << " .. ";
	som.readSemiXMLandWriteRawText(*xmlIn, *txtOut);
    std::cerr << "done" << std::endl;

    std::cerr << "Writing to " << args[1] << " .. ";
	som.writeData(*soOut);
    std::cerr << "done" << std::endl;

    return true;
}

//------------------------------------------------------------------------------
// Export Handler
//------------------------------------------------------------------------------
ExportHandler::ExportHandler(void)
{
    std::vector<std::string> opts;
    opts.push_back("-h");
    opts.push_back("--help");

    std::vector<std::string> argOpts;
#ifdef WITH_ZLIB
    argOpts.push_back("-c");
#endif

    optParser.setAllowedOptions(opts, argOpts);
}

void
ExportHandler::printUsage(void)
{
    std::cerr
		<< "Usage: som export <input_so> <input_txt> <output_semi_xml>       \n"
		<< "                                                                 \n"
    	<< "Use '-' as the file name to use standard input/output            \n"
		<< "                                                                 \n"
    	<< "Options:                                                         \n"
#ifdef WITH_ZLIB
		<< "   -c (r|z)(r|z)(r|z) : treat each of input_so, input_txt, and   \n"
        << "                output_semi_xml as a gzipped file ('z') or       \n"
        << "                a raw text file ('r') (default: -c rrr)          \n"
#endif
    	<< "   -h, --help: show this help                                    \n"
        ;
}

bool
ExportHandler::exec(const std::vector<std::string> &commandLineArgv)
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

	if (args.size() != 3) {
		printUsage();
		exit(1);
	}

    std::string compressSpec("rrr");
#ifdef WITH_ZLIB
    if (opts.size() == 1 && opts.front().first == "-c") {
        compressSpec = opts.front().second;
        if (compressSpec.size() != 3
            || (compressSpec[0] != 'r' && compressSpec[0] != 'z')
            || (compressSpec[1] != 'r' && compressSpec[1] != 'z')
            || (compressSpec[2] != 'r' && compressSpec[2] != 'z')) {
            std::cerr << "som export: argument of -c option must match the pattern "
                         " /(r|z)(r|z)(r|z)/" << std::endl;
            return false;
        }
    }
    else {
        assert(false); // never happens
    }
#endif

	///-------------------------------------------------------------------------
	/// Read data & export
	///-------------------------------------------------------------------------
    StreamManager streamManager;
	// StandOffManager som;

#ifdef WITH_ZLIB
	std::istream *soIn  = (compressSpec[0] == 'z')
                        ? streamManager.getGzInputStream(args[0])
                        : streamManager.getInputStream(args[0]);
	std::istream *txtIn = (compressSpec[1] == 'z')
                        ? streamManager.getGzInputStream(args[1])
                        : streamManager.getInputStream(args[1]);

	std::ostream *out   = (compressSpec[2] == 'z')
                        ? streamManager.getGzOutputStream(args[2])
                        : streamManager.getOutputStream(args[2]);
#else
	std::istream *soIn  = streamManager.getInputStream(args[0]);
	std::istream *txtIn = streamManager.getInputStream(args[1]);

	std::ostream *out   = streamManager.getOutputStream(args[2]);
#endif

#if 0
	std::cerr << "Reading tag data from " << args[0] << " .. " << std::endl;
	som.readDataStrictly(*soIn);
	std::cerr << "done (" << som.getNumTags() << " tags)" << std::endl;

    std::cerr << "Writing semi-XML .. " << std::endl;
	som.writeSemiXML(*txtIn, *out);
    std::cerr << "done" << std::endl;
#endif
    
    /// memory efficient version; no validity check
    StandOffManager::writeSemiXML(*txtIn, *soIn, *out);

    return true;
}
