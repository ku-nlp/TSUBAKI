#ifndef OptionParser_h__
#define OptionParser_h__

#include <utility>
#include <vector>
#include <string>
#include <set>

typedef std::vector< std::pair<std::string, std::string> > Options;
typedef Options::const_iterator OptItr;

class OptionParser {
public:
    void setAllowedOptions(
		const std::vector<std::string> &allowedOpotions,
		const std::vector<std::string> &allowedArgumentOptions);

    void parseArgv(
        const std::vector<std::string> &argv,
        Options &options,
        std::vector<std::string> &arguments) const;
private:
    std::set<std::string> allowedOpts;
    std::set<std::string> allowedArgOpts;
};

#endif // OptionParser_h__
