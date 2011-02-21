#include <queue>
#include <map>
#include <iterator>
#include <algorithm>
#include <cassert>

#include "som_util.hpp"
#include "TagData.hpp"
#include "MergeHandler2.hpp"

class TagOrderFinder {
public:
	TagOrderFinder(const std::vector<std::string> &tagOrder)
	{
		for (unsigned i = 0; i < tagOrder.size(); ++i) {
			_order[tagOrder[i]] = i + 1;
		}
	}

	unsigned operator()(const std::string &name) const
	{
		std::map<std::string, unsigned>::const_iterator it = _order.find(name);
		if (it == _order.end()) {
			return 0; /// unknown tag
		}
		else {
			return it->second;
		}
	}

private:
	std::map<std::string, unsigned> _order;
};

class Comp; /// Forward decl

struct TagSeq {
	TagData _top;
	unsigned _order; /// chached tag order of _top
	unsigned _fileNo;

	bool init(
		std::istream *ist,
		unsigned fileNo,
		const TagOrderFinder &findTagOrder
	) {
		_fileNo = fileNo;

		std::string line;
		if (! findNextNonEmptyLine(ist, line)) {
			return false;
		}

		if (! _top.parseStandOffLine(line)) {
			throw MergeHandler2::FormatError("line format error", _fileNo, line);
		}

		_order = findTagOrder(_top.getName());

		return true;
	}

	bool goNext(
		std::istream *ist,
		const TagOrderFinder &findTagOrder,
		const Comp &comp);

private:
	bool findNextNonEmptyLine(std::istream *ist, std::string &line)
	{
		line.clear();

		while (std::getline(*ist, line)) {
			if (! line.empty()) {
				return true;
			}
		}

		return false;
	}
};

class Comp {
public:

	int compSpan(const TagData::Span &s1, const TagData::Span &s2) const
	{
		if (s1.first < s2.first) {
			return 1;
		}
		else if (s1.first > s2.first) {
			return -1;
		}
		else { /// s1.first == s2.first
			
			if (s1.second > s2.second) { /// s1 contains s2
				return 1;
			}
			else if (s1.second < s2.second) { /// s2 contains s1
				return -1;
			}
			else { /// Same span
				return 0;
			}
		}
	}

	/// True <=> t1 comes *after* t2
	bool operator()(const TagSeq &t1, const TagSeq &t2) const
	{
		int spanComp = compSpan(t1._top.getSpan(), t2._top.getSpan());

		if (spanComp != 0) {
			return spanComp < 0;
		}
		else { /// Same span
				
			if (t1._top.isEmptyTag()) {
				return t1._fileNo > t2._fileNo;
			}
			else { /// Non-empty tag

				if (t1._order > t2._order) {
					return true;
				}
				else if (t1._order < t2._order) {
					return false;
				}
				else {
					return t1._fileNo > t2._fileNo;
				}
			}
		}
	}
};

inline
bool TagSeq::goNext(
	std::istream *ist,
	const TagOrderFinder &findTagOrder,
	const Comp &comp
) {

	std::string line;
	if (! findNextNonEmptyLine(ist, line)) {
		return false;
	}

	TagData next;
	if (! next.parseStandOffLine(line)) {
		throw MergeHandler2::FormatError("line format error", _fileNo, line);
	}

	unsigned nextOrder = findTagOrder(next.getName());

	int spanComp = comp.compSpan(_top.getSpan(), next.getSpan());

	if (spanComp < 0) {
		throw MergeHandler2::FormatError("tags not sorted", _fileNo, line);
	}

	if (spanComp == 0 && ! _top.isEmptyTag() && _order > nextOrder) {
		/// Same, non-empty span, and inverted tag order
		throw MergeHandler2::FormatError("not sorted", _fileNo, line);
	}

	_top = next;
	_order = nextOrder;

	return true;
}

MergeHandler2::MergeHandler2(void)
{
    std::vector<std::string> opts;
    opts.push_back("-h");
    opts.push_back("--help");

    std::vector<std::string> argOpts;
    argOpts.push_back("-t");
#ifdef WITH_ZLIB
    argOpts.push_back("-c");
#endif

    optParser.setAllowedOptions(opts, argOpts);
}

void
MergeHandler2::printUsage(void)
{
    std::cerr
		<< "Usage: som merge2 [options] <so_1> <so_2> [ .. <so_n> ] <out_so> \n"
		<< "                                                                 \n"
    	<< "Use '-' as the file name to use standard input/output            \n"
		<< "                                                                 \n"
    	<< "Options:                                                         \n"
		<< "   -t file    : use 'file' as the tag-order file                 \n"
#ifdef WITH_ZLIB
		<< "   -c (r|z)+  : treat each of so_1, .., so_n, and out_so as      \n"
        << "                a gzipped file ('z') or a raw text file ('r')    \n"
        << "                (default: -c rr..r)                              \n"
#endif
    	<< "   -h, --help : show this help                                   \n"
#ifdef WITH_ZLIB
        << "                                                                 \n"
        << "Example:                                                         \n"
        << "   som merge2 -c zrz input1.so.gz input2.so - > output.so.gz     \n"
#endif
        ;
}

bool
MergeHandler2::exec(const std::vector<std::string> &commandLineArgv)
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

	if (args.size() < 3) {
		printUsage();
        return false;
	}

    StreamManager streamManager;

	std::vector<std::string> tagOrder;
#ifdef WITH_ZLIB
    std::vector<char> compressSpec('r', args.size());
#endif

	for (OptItr iter = opts.begin(); iter != opts.end(); ++iter) {

		if (iter->first == "-h" or iter->first == "--help"){
			/// Never happens
            assert(false);
		}
		else if (iter->first == "-t") {

			std::istream *tagOrderFile
                = streamManager.getInputStream(iter->second);

			std::copy(
				std::istream_iterator<std::string>(*tagOrderFile),
				std::istream_iterator<std::string>(),
				std::back_inserter(tagOrder));
		}
#ifdef WITH_ZLIB
        else if (iter->first == "-c") {
            if (iter->second.size() != args.size()) {
                std::cerr << "som merge2: length of -c argument must be the same "
                          << "as the number of input standoff + 1 (\"+1\" for the "
                          << "output standoff)" << std::endl;
                return false;
            }
            for (std::string::const_iterator ch = iter->second.begin();
                    ch != iter->second.end(); ++ch) {
                if (*ch != 'r' && *ch != 'z') {
                    std::cerr << "som merge2: -c argument doens not match /(r|z)+/"
                              << std::endl;
                    return false;
                }
            }
            compressSpec = std::vector<char>(iter->second.begin(), iter->second.end());
        }
#endif
		else {
			/// Never happens
            assert(false);
		}
	}

	///-------------------------------------------------------------------------
	/// Merge sort
	///-------------------------------------------------------------------------

	std::vector<std::istream *> input(args.size() - 1);
	for (unsigned i = 0; i < input.size(); ++i) {
#ifdef WITH_ZLIB
        input[i] = (compressSpec[i] == 'z')
                 ? streamManager.getGzInputStream(args[i])
                 : streamManager.getInputStream(args[i]);
#else
		input[i] = streamManager.getInputStream(args[i]);
#endif
	}

#ifdef WITH_ZLIB
	std::ostream *output = (compressSpec.back() == 'z')
                         ? streamManager.getGzOutputStream(args.back())
                         : streamManager.getOutputStream(args.back());
#else
	std::ostream *output = streamManager.getOutputStream(args.back());
#endif

	try {
        merge(tagOrder, input, *output);
	}
	catch (const FormatError &e)
	{
		std::cerr
			<< "som merge2: " << e.getType() << ": in "
			<< args[e.getFileNo()] << std::endl
			<< "line: " << e.getLine() << std::endl;

        return false;
	}

    return true;
}

void
MergeHandler2::merge(
    const std::vector<std::string> &tagOrder,
    const std::vector<std::istream*> &in,
    std::ostream &out
) {
	TagOrderFinder findTagOrder(tagOrder);
	std::priority_queue<TagSeq, std::vector<TagSeq>, Comp> queue;

    for (unsigned i = 0; i < in.size(); ++i) {
        TagSeq ts;
        if (ts.init(in[i], i, findTagOrder)) {
            queue.push(ts);
        }
    }

    while (! queue.empty()) {
        TagSeq ts = queue.top();
        queue.pop();

        ts._top.writeStandOffLine(out);

        if (ts.goNext(in[ts._fileNo], findTagOrder, Comp())) {
            queue.push(ts);
        }
    }
}
