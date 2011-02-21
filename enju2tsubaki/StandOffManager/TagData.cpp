#include <sstream>
#include "TagData.hpp"

inline
bool parseNameAttrs(
	std::istringstream &iss,
	std::string &name,
	std::string &attrs
) {
	if (! (iss >> name)) {
		return false;
	}

	/// get all the attributes if exist, replacing all '\n' to a whitespace
    /// TODO: check the XML spec if this is ok
	std::string as;
    std::string line;
	while (std::getline(iss, line)) {
        as += " " + line;
    }

    /// many tags don't have any characters after the tag name
    if (as.empty()) {
        attrs.clear();
        return true;
    }

	/// skip heading spaces
	unsigned head = 0;
	while (head < as.size() && std::isspace(as[head])) {
	    ++head;
	}

    /// remove tailing spaces
    int tail = as.size() - 1;
    while (tail >= 0 && std::isspace(as[tail])) {
        --tail;
    }

    if (static_cast<int>(head) <= tail) {
	    attrs = as.substr(head, tail - head + 1);
    }
    else { /// tail == -1: all chars are 'space'
        attrs.clear();
    }

	return true;
}

bool TagData::parseStandOffLine(const std::string &line)
{
	std::istringstream iss(line);
	if (! (iss >> span.first >> span.second)) {
		return false;
	}

	return parseNameAttrs(iss, name, attributes);
}

bool TagData::parseTag(const std::string &tag)
{
	std::istringstream iss(tag);

	return parseNameAttrs(iss, name, attributes);
}
