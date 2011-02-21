#ifndef COMMAND_HANDLER_HPP
#define COMMAND_HANDLER_HPP

#include <vector>

class CommandHandler {
public:
	virtual ~CommandHandler(void) {}
    virtual void printUsage(void) = 0;
	virtual bool exec(const std::vector<std::string> &argv) = 0;
};

#endif // COMMAND_HANDLER_HPP
