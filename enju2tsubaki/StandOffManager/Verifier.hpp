#ifndef Verifier_h__
#define Verifier_h__

#include "CommandHandler.hpp"
#include "OptionParser.hpp"

class Verifier : public CommandHandler {
public:
    Verifier(void);
    void printUsage(void);
    bool exec(const std::vector<std::string> &argv);
private:
    OptionParser optParser;
};

#endif // Verifier_h__
