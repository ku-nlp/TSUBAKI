#ifndef MergeHandler2_h__
#define MergeHandler2_h__

#include "CommandHandler.hpp"
#include "OptionParser.hpp"

class MergeHandler2 : public CommandHandler {
public:
    MergeHandler2(void);
    void printUsage(void);
    bool exec(const std::vector<std::string> &argv);

public:

    class FormatError {
    public:
	    FormatError(
		    const std::string &type,
		    unsigned fileNo,
		    const std::string &line
	    )
		    : _type(type)
		    , _fileNo(fileNo)
		    , _line(line)
	    {}
    
	    std::string getType(void) const { return _type; }
	    unsigned getFileNo(void) const { return _fileNo; }
	    std::string getLine(void) const { return _line; }

    private:
	    std::string _type;
	    unsigned _fileNo;
	    std::string _line;
    };

    /// On input standoff format error -> throw FormatError
    static void merge(
        const std::vector<std::string> &tagOrder,
        const std::vector<std::istream*> &in,
        std::ostream &out);

private:
    OptionParser optParser;
};

#endif // MergeHandler2_h__
