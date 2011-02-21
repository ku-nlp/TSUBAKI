#ifndef TAG_DATA_HPP
#define TAG_DATA_HPP

#include <vector>
#include <map>
#include <string>
#include <iostream>
#include <stdexcept>
#include <sstream>

class TagData {
public:
	typedef std::pair<unsigned int, unsigned int> Span;

	TagData(void) {}

    TagData(
		const std::string &tagName,
        const std::string &attrs,
        Span tagSpan
	) :
		name(tagName),
		attributes(attrs),
		span(tagSpan)
    {}

    std::string getName(void) const { return name; }
    std::string getAttributes(void) const { return attributes; }
    Span getSpan(void) const { return span; }

	bool hasAttributes(void) const { return ! attributes.empty(); }

	bool isEmptyTag(void) const { return span.first == span.second; }

    void setSpan(Span domain) { span = domain; }
    void setSpan(unsigned begin, unsigned end) { span = Span(begin, end); }

	bool parseStandOffLine(const std::string &line);

	/// parse inside of '<' and '>' (or "/>")
	bool parseTag(const std::string &tagString);

	/// write a stand-off format tag, including the last '\n'
	std::ostream &writeStandOffLine(std::ostream &ost) const
	{
		ost << span.first << '\t' << span.second << '\t' << getName();
		if (! attributes.empty()) {
			ost << '\t' << attributes;
		}
		ost << '\n';

		return ost;
	}

private:
    std::string name;
    std::string attributes;
    Span span;
};

class StandOffFormatError : public std::runtime_error {
public:
    StandOffFormatError(const std::string &msg) : std::runtime_error(msg) {}
};

/// A simple wrapper of std::istream, which skips empty lines and throws
/// StandOffFormatError when it finds a wrongly formatted line
class TagStream {
public:
    TagStream(std::istream &ist) : _ist(ist), _lineNo(0) {}

    TagStream &read(TagData &t)
    {
        std::string line;
        while (std::getline(_ist, line)) {

            ++_lineNo;

            if (line.empty()) {
                continue;
            }

            if (! t.parseStandOffLine(line)) {
                std::ostringstream msg;
                msg << "Standoff format error at line "
                        << _lineNo << ":" << std::endl
                    << line << std::endl;
                throw StandOffFormatError(msg.str());
            }

            break;
        }

        return *this;
    }

    operator bool() const { return static_cast<bool>(_ist); }

    void setLineNumber(unsigned int n) { _lineNo = n; }
    unsigned int getLineNumber(void) const { return _lineNo; }

private:
    std::istream &_ist;
    unsigned int _lineNo;
};

inline
TagStream &operator>>(TagStream &tst, TagData &tag)
{
    return tst.read(tag);
}

class AIsLessThanB {
public:

    AIsLessThanB(const std::vector<std::string>& order)
    {
		/// Reserve 0: when a tag name is not in 'order', its order is 0
		for (unsigned i = 0; i < order.size(); ++i) {
			tagOrder[order[i]] = i + 1;
		}
	}

    bool operator()(const TagData &a, const TagData &b) const
	{
        if (a.getSpan().first < b.getSpan().first) {
            return true;
        }
        else if (a.getSpan().first > b.getSpan().first) {
            return false;
        }
        else { /// a.begin == b.begin
            if (a.getSpan().second > b.getSpan().second) {
                return true;
            }
            else if (a.getSpan().second < b.getSpan().second) {
                return false;
            }
            else { /// a.span == b.span

				/// XXX: 
				///  1. Not a strict weak ordering: see 
				///      http://www.sgi.com/tech/stl/StrictWeakOrdering.html
				///  2. When a is in the order list but b is not, then b < a.
				///    (When b is in the order list but a is not, then a < b.)

                // std::string aName = a.getName();
                // std::string bName = b.getName();
                // std::vector<std::string>::const_iterator iter;
                // for (iter = tagOrder.begin(); iter != tagOrder.end(); ++iter) {
                //    if (*iter == aName) {
                //    	return true;
                //    }
                //    else if (*iter == bName) {
                //    	return false;
                //    }
                // }

				return operator()(a.getName(), b.getName());
            }
        }
    }

	/// Compare the tag names only (for tags with the same span)
    bool operator()(const std::string &a, const std::string &b) const
	{
		return getOrderValue(a) < getOrderValue(b);
	}

	/// 3-way comparison between two tag names
	///  1: a < b
	///  0: a == b
	/// -1: b < a
	int compare3way(const std::string &a, const std::string &b) const
	{
		unsigned aOrder = getOrderValue(a);
		unsigned bOrder = getOrderValue(b);

		if (aOrder < bOrder) {
			return 1;
		}
		else if (aOrder > bOrder) {
			return -1;
		}
		else {
			return 0;
		}
	}

private:
	unsigned getOrderValue(const std::string &name) const
	{
		typedef std::map<std::string, unsigned>::const_iterator MItr;

		MItr it = tagOrder.find(name);
		if (it == tagOrder.end()) {
			return 0;
		}
		else {
			return it->second;
		}
	}

private:
	std::map<std::string, unsigned> tagOrder;
};


#endif /*TAG_DATA_HPP*/
