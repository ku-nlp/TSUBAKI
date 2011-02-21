#ifndef som_util_hpp__
#define som_util_hpp__

#include <iostream>
#include <stdexcept>
#include <vector>
#include <fstream>

#include "OptionParser.hpp"

/// Check if opts contains "-h" or "--help"
bool showHelp(const Options &opts);


class StdInUsageError : public std::runtime_error {
public:
    StdInUsageError(void)
        : std::runtime_error(
	        "som: '-' argument cannot be used more than once "
            "among the input files")
    {}
};

class StdOutUsageError : public std::runtime_error {
public:
    StdOutUsageError(void)
        : std::runtime_error(
	        "som: '-' argument cannot be used more than once among "
			"the output files")
    {}
};

/// Keep pointers to streams and release all the known stream pointers 
/// except for &std::cin and &std::cout in its destructor
class StreamManager {
public:
    StreamManager(void);

    ~StreamManager(void);

    /// Open a file stream and return a pointer to it when the 
    /// filename is not "-", or otherwise return &std::cin or &std::cout
    ///
    /// (note 1) Do *NOT* release the returned pointers by yourself!!
    /// (note 2) Std{In,Out}UsageError is thrown on the second request
    ///         for "-" as input/output stream
    std::istream *getInputStream(const std::string &fileName);
    std::ostream *getOutputStream(const std::string &fileName);

#ifdef WITH_ZLIB
    std::istream *getGzInputStream(const std::string &fileName);
    std::ostream *getGzOutputStream(const std::string &fileName);
#endif

private:
    std::vector<std::istream*> iss;
    std::vector<std::ostream*> oss;

    bool stdInIsUsed;
    bool stdOutIsUsed;
};

#endif // som_util_hpp__
