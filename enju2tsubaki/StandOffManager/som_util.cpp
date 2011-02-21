#include <fstream>
#include <cstdlib>
#include "som_util.hpp"

#ifdef WITH_ZLIB
#   include "GzStream.hpp"
#endif

//------------------------------------------------------------------------------
// utilities
//------------------------------------------------------------------------------

typedef std::vector<std::istream*> IStreams;
typedef std::vector<std::ostream*> OStreams;

StreamManager::StreamManager(void)
    : stdInIsUsed(false)
    , stdOutIsUsed(false)
    {}

StreamManager::~StreamManager(void)
{
    for (IStreams::iterator it = iss.begin(); it != iss.end(); ++it) {
        delete *it;
    }

    for (OStreams::iterator it = oss.begin(); it != oss.end(); ++it) {
        delete *it;
    }
}

std::istream *
StreamManager::getInputStream(const std::string &fileName)
{
    if (fileName == "-") {
        if (stdInIsUsed) {
            throw StdInUsageError();
        }
        return &std::cin;
    }
    else {
        std::ifstream *ifs = new std::ifstream(fileName.c_str());
        if (! *ifs) {
            throw std::runtime_error("som: cannot open " + fileName);
        }

        iss.push_back(ifs);

        return ifs;
    }
}

std::ostream *
StreamManager::getOutputStream(const std::string &fileName)
{
    if (fileName == "-") {
        if (stdOutIsUsed) {
            throw StdOutUsageError();
        }
        return &std::cout;
    }
    else {
        std::ofstream *ofs = new std::ofstream(fileName.c_str());
        if (! *ofs) {
            throw std::runtime_error("som: cannot open " + fileName);
        }

        oss.push_back(ofs);

        return ofs;
    }
}

#ifdef WITH_ZLIB

std::istream *
StreamManager::getGzInputStream(const std::string &fileName)
{
    if (fileName == "-") {
        if (stdInIsUsed) {
            throw StdInUsageError();
        }
        std::istream *gzCin = new IGzStream(std::cin);

        if (! *gzCin) {
            throw std::runtime_error("som: cannot open gz-stream on standard input");
        }

        // 'delete gzCin' will flush the buffer and destruct only the outer object
        iss.push_back(gzCin);

        return gzCin;
    }
    else {
        std::istream *igfs = new IGzFStream(fileName);
        if (! *igfs) {
            throw std::runtime_error("som: cannot open " + fileName);
        }

        iss.push_back(igfs);

        return igfs;
    }
}

std::ostream *
StreamManager::getGzOutputStream(const std::string &fileName)
{
    if (fileName == "-") {
        if (stdOutIsUsed) {
            throw StdOutUsageError();
        }
        // return &std::cout;
        std::ostream *gzCout = new OGzStream(std::cout);
        if (! *gzCout) {
            throw std::runtime_error("som: cannot open gz-stream on standard output");
        }

        // 'delete gzCout' will flush the buffer and destruct only the outer object
        oss.push_back(gzCout);

        return gzCout;
    }
    else {
        std::ostream *ogfs = new OGzFStream(fileName);
        if (! *ogfs) {
            throw std::runtime_error("som: cannot open " + fileName);
        }

        oss.push_back(ogfs);

        return ogfs;
    }
}

#endif // WITH_ZLIB

bool showHelp(const Options &opts)
{
	for (OptItr it = opts.begin(); it != opts.end(); ++it) {
		if (it->first== "-h" || it->first == "--help") {
			return true;
		}
	}

	return false;
}
