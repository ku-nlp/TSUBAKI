#ifndef SORT_HANDLER_HPP
#define SORT_HANDLER_HPP

#include "CommandHandler.hpp"
#include "OptionParser.hpp"

class SortHandler : public CommandHandler {
public:
    SortHandler(void);
    void printUsage(void);
    bool exec(const std::vector<std::string> &argv);
private:
    OptionParser optParser;
};

class MergeHandler : public CommandHandler {
public:
    MergeHandler(void);
    void printUsage(void);
    bool exec(const std::vector<std::string> &argv);
private:
    OptionParser optParser;
};

class ClipOutHandler : public CommandHandler {
public:
    ClipOutHandler(void);
    void printUsage(void);
    bool exec(const std::vector<std::string> &argv);
private:
    OptionParser optParser;
};

class UniteHandler : public CommandHandler {
public:
    UniteHandler(void);
    void printUsage(void);
    bool exec(const std::vector<std::string> &argv);
private:
    OptionParser optParser;
};

class ImportHandler : public CommandHandler {
public:
    ImportHandler(void);
    void printUsage(void);
    bool exec(const std::vector<std::string> &argv);
private:
    OptionParser optParser;
};

class ExportHandler : public CommandHandler {
public:
    ExportHandler(void);
    void printUsage(void);
    bool exec(const std::vector<std::string> &argv);
private:
    OptionParser optParser;
};

#endif // SORT_HANDLER_HPP
