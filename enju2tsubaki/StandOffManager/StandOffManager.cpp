#include <sstream>
#include <stack>
#include <fstream>
#include <utility>
#include <algorithm>
#include <iostream>
#include <list>
#include <iterator>
#include <map>
#include <stdexcept>
#include <cassert>
#include <limits>

#include "StandOffManager.hpp"
#include "TagData.hpp"
#include "Mapper.hpp"

////////////////////////////////////////////////////////////////////////////////
/// Util
////////////////////////////////////////////////////////////////////////////////
template<class FStreamType>
void
checkFile(const FStreamType &f, const std::string &fileName)
{
	if (! f) {
		throw std::runtime_error("cannot open file \"" + fileName + "\"");
	}
}

void throwFormatErrorException(
	unsigned int lineNo,
	const std::string &line,
	const std::string &errorType
) {
    std::ostringstream msg;
    msg << "Error: tags are not properly ordered in the stand-off file"
		        << "(" << errorType << ")" << std::endl
        << "in line " << lineNo << ":" << std::endl
        << line << std::endl
	    << "Error type = " << errorType << std::endl;

    throw std::runtime_error(msg.str());
}

////////////////////////////////////////////////////////////////////////////////
/// Getter
////////////////////////////////////////////////////////////////////////////////
void
StandOffManager::getData(std::vector<TagData> &tags) const
{
	tags = tagsData;
}

////////////////////////////////////////////////////////////////////////////////
/// Sort functions
////////////////////////////////////////////////////////////////////////////////
void
StandOffManager::sort()
{
    std::stable_sort(tagsData.begin(), tagsData.end(), AIsLessThanB(tagOrder));
}

////////////////////////////////////////////////////////////////////////////////
/// Escape/Un-escape
////////////////////////////////////////////////////////////////////////////////
#if 0
inline
void
writeConvertingEscapeChar(char c, std::ostream& os)
{
	switch (c) {
		case '<'    : os << "&lt;"      ; break;
    	case '>'    : os << "&gt;"      ; break;
		case '&'    : os << "&amp;"     ; break;
		case '"'    : os << "&quot;"    ; break;
		case '\''   : os << "&apos;"    ; break;
		default     : os << c           ; break;
    }

	return;
}

inline
void
writeConvertingAttrEscapeChar(char c, std::ostream& os)
{
	switch (c) {
		case '<'    : os << "&lt;"      ; break;
    	case '>'    : os << "&gt;"      ; break;
		case '&'    : os << "&amp;"     ; break;
		/// Matsubayashi's original does not quote '"'. Why?
		// case '"' : os << "&quot;"    ; break;
		case '\''   : os << "&apos;"    ; break;
		default     : os << c           ; break;
    }

	return;
}

inline
void
writeConvertingElementEscapeChar(char c, std::ostream& os)
{
	switch (c) {
        case '<'    : os << "&lt;"      ; break;
    	// case '>' : os << "&gt;"      ; break;
		case '&'    : os << "&amp;"     ; break;
		case '"'    : os << "&quot;"    ; break;
		default     : os << c           ; break;
    }

	return;
}
#endif

/// 2007.11.27: We need to escape only '<' and '&'
inline
void
writeCharWithEscaping(char c, std::ostream& os)
{
	switch (c) {
        case '<'    : os << "&lt;"   ; break;
    	// case '>' : os << "&gt;"   ; break;
		case '&'    : os << "&amp;"  ; break;
		// case '"' : os << "&quot;" ; break;
		default     : os << c        ; break;
    }

	return;
}

// ascii hex-string to digit conversion with error check
unsigned int getUscCodeHex(const std::string &s)
{
	if (s.empty()) {
		throw std::runtime_error("empty character reference: &#x;");
	}

	unsigned int code = 0;
	for (std::string::const_iterator ch = s.begin(); ch != s.end(); ++ch) {
		code *= 16;
        if ('0' <= *ch && *ch <= '9') {
            code += (*ch - '0');
        }
        else if ('a' <= *ch && *ch <= 'f') {
			code += (*ch - 'a' + 10);
		}
		else if ('A' <= *ch && *ch <= 'F') {
			code += (*ch - 'A' + 10);
		}
		else {
			throw std::runtime_error("invalid character reference: &#x" + s + ";");
		}

		if (code > 0x10ffff) { // 0x10ffff: unicode-max
			throw std::runtime_error("too large character reference code: &#x" + s + ";");
		}
	}

	return code;
}

// ascii decimal-string to digit conversion with error check
unsigned int getUscCodeDec(const std::string &s)
{
	if (s.empty()) {
		throw std::runtime_error("empty character reference: &#;");
	}

	unsigned int code = 0;
	for (std::string::const_iterator ch = s.begin(); ch != s.end(); ++ch) {
		code *= 10;
		if ('0' <= *ch && *ch <= '9') {
			code += (*ch - '0');
		}
		else {
			throw std::runtime_error("invalid character reference: &#" + s + ";");
		}

		if (code > 0x10ffff) { // 0x10ffff: unicode-max
			throw std::runtime_error("too large character reference code: &#" + s + ";");
		}
	}

	return code;
}

// adapted from iconv/utf-8/ucs_to_utf8.c
std::string encodeUtf8(unsigned int c)
{
	std::string s;
	if (c <= 0x7f) { /// 7bit
		s += (char) c;
	}
	else if (c <= 0x7ff) { /// 11bit
		s += (char) (0xc0 | ((c & 0x07c0) >> 6));
		s += (char) (0x80 |  (c & 0x003f));
	}
	else if (c <= 0x00ffff) { /// 16bit
		s += (char) (0xe0 | ((c & 0x0f000) >> 12));
		s += (char) (0x80 | ((c & 0x00fc0) >> 6));
		s += (char) (0x80 |  (c & 0x0003f));
	}
	else if (c <= 0x1fffff) { /// 21bit
		s += (char) (0xf0 | ((c & 0x01c0000) >> 18));
		s += (char) (0x80 | ((c & 0x003f000) >> 12));
		s += (char) (0x80 | ((c & 0x0000fc0) >> 6));
		s += (char) (0x80 |  (c & 0x000003f));
	}
	else if (c <= 0x3ffffff) { /// 26bit
		s += (char) (0xf8 | ((c & 0x03000000) >> 24));
		s += (char) (0x80 | ((c & 0x00fc0000) >> 18));
		s += (char) (0x80 | ((c & 0x0003f000) >> 12));
		s += (char) (0x80 | ((c & 0x00000fc0) >> 6));
		s += (char) (0x80 |  (c & 0x0000003f));
	}
	else { /// 31bit
		s += (char) (0xfc | ((c & 0x40000000) >> 30));
		s += (char) (0x80 | ((c & 0x3f000000) >> 24));
		s += (char) (0x80 | ((c & 0x00fc0000) >> 18));
		s += (char) (0x80 | ((c & 0x0003f000) >> 12));
		s += (char) (0x80 | ((c & 0x00000fc0) >> 6));
		s += (char) (0x80 |  (c & 0x0000003f));
	}

	return s;
}

std::string unescape(const std::string &escapeSeq)
{
    if (escapeSeq == "lt") {
        return "<";
    }
    else if (escapeSeq == "gt") {
        return ">";
    }
    else if (escapeSeq == "amp") {
        return "&";
    }
    else if (escapeSeq == "quot") {
        return "\"";
    }
    else if (escapeSeq == "apos") {
        return "\'";
    }
	else if (escapeSeq.size() >= 2 && escapeSeq[0] == '#') { // ISO/IEC 10646 char code
		unsigned int code = (escapeSeq[1] == 'x') ? getUscCodeHex(escapeSeq.substr(2))
			                                      : getUscCodeDec(escapeSeq.substr(1));
		return encodeUtf8(code);
	}
    else{
        //XXX: no throw operator (fixed 2008.11.08)
        throw std::runtime_error("unknown escape sequence \"" + escapeSeq + "\"");
    }

    /// Never reached
    return std::string();
}

/// ch will point to the next character after the escape sequence
std::string
convertEscapeChar(
    std::string::const_iterator& ch,
    const std::string::const_iterator& end
) {
    std::string escapeSeq; /// will be the string between '&' and ';'
    while (ch != end && *ch != ';') {
        escapeSeq += *ch++;
    }

    if (ch == end) {
        throw std::runtime_error(
            "input xml includes a non-terminated escape sequence");
    }

    ++ch; /// skip ';'

    return unescape(escapeSeq);
}

////////////////////////////////////////////////////////////////////////////////
/// Export 
////////////////////////////////////////////////////////////////////////////////
inline
std::string startTagString(const TagData &t)
{
	assert(! t.isEmptyTag());

    return "<" + t.getName()
               + (t.hasAttributes() ? " " + t.getAttributes() : "")
               + ">";
}

inline
std::string emptyTagString(const TagData &t)
{
	assert(t.isEmptyTag());

    return "<" + t.getName()
               + (t.hasAttributes() ? " " + t.getAttributes() : "")
               + "/>";
}

// TODO: move to TagData.hpp
template<class SequenceT>
class SequenceTagIterator {
public:
    SequenceTagIterator(typename SequenceT::const_iterator begin, typename SequenceT::const_iterator end)
        : _curr(begin)
        , _end(end)
    {}

    const TagData *operator->(void) const { return &*_curr; }
    const TagData &operator*(void) const { return *_curr; }
    const SequenceTagIterator &operator++(void) { ++_curr; return *this; }
    bool end(void) const { return _curr == _end; }
private:
    typename SequenceT::const_iterator _curr;
    typename SequenceT::const_iterator _end;
};

class StreamTagIterator {
public:
    StreamTagIterator(std::istream &ist)
        : _stream(ist)
        , _end(false)
    {
        if (! (_stream >> _curr)) {
            _end = true;
        }
    }

    const TagData *operator->(void) const { return &_curr; }
    const TagData &operator*(void) const { return _curr; }
    const StreamTagIterator &operator++(void)
    {
        if (! (_stream >> _curr)) {
            _end = true;
        }

        return *this;
    }
    bool end(void) const { return _end; }

private:
    TagData _curr;
    TagStream _stream;
    bool _end;
};

template<class IteratorT>
void writeSemiXMLImpl(std::istream &rawTxt, IteratorT tag, std::ostream &semiXML)
{
	typedef std::map<unsigned int, std::list<std::string> > EndTagList;
    EndTagList endTagList;

    unsigned int charCount = 0;

    // std::vector<TagData>::const_iterator tag = tagsData.begin();

    while (! rawTxt.eof()) {

		/// Empty tags go first
		while (! tag.end() // tag != tagsData.end()
				&& charCount == tag->getSpan().first
				&& tag->isEmptyTag()) {

			semiXML << emptyTagString(*tag);

			++tag;
		}

		/// Then end tags
        if (! endTagList.empty()) {

			/// Check the properness of the tag order.
			/// If the input was already checked, this check is unnecessary.
			if (charCount > endTagList.begin()->first) {
				throw std::runtime_error("stand-off tags are badly ordered");
			}

			if (charCount == endTagList.begin()->first) {

				std::list<std::string> endTags;
				endTagList.begin()->second.swap(endTags);

				endTagList.erase(endTagList.begin());

				for (std::list<std::string>::const_iterator t = endTags.begin();
						t != endTags.end(); ++t) {

            		semiXML << "</" << *t << ">";
				}
			}
        }

		/// Start tags & empty tags
        // while (tag != tagsData.end() && charCount == tag->getSpan().first) {
        while (! tag.end() && charCount == tag->getSpan().first) {

			if (tag->isEmptyTag()) {
				semiXML << emptyTagString(*tag);
			}
			else {
				semiXML << startTagString(*tag);
				endTagList[tag->getSpan().second].push_front(tag->getName());
			}

            ++tag;
        }

		/// Finally, the character
   		char c;
        if (rawTxt.get(c)) {
            writeCharWithEscaping(c, semiXML);
            ++charCount;
        }
    }

	/// there may be some empty tags here
	// for ( ; tag != tagsData.end(); ++tag) {
	for ( ; ! tag.end(); ++tag) {

		if (tag->getSpan().first != charCount
				|| tag->getSpan().second != charCount) {
			throw std::runtime_error(
                "Out-of-text annotation in the stand-off data");
		}

		semiXML << emptyTagString(*tag);
	}

	/// there may be some end tags here
	if (! endTagList.empty()) {
		
		if (endTagList.size() != 1 || endTagList.begin()->first != charCount) {
			throw std::runtime_error(
                "Out-of-text annotation in the stand-off data");
		}

		const std::list<std::string> &endTags = endTagList.begin()->second;
		for (std::list<std::string>::const_iterator t = endTags.begin();
				t != endTags.end(); ++t) {
			semiXML << "</" << *t << ">";
		}
	}
}

void
StandOffManager::writeSemiXML(std::istream &rawTxt, std::istream &isSoff, std::ostream &semiXML)
{
    writeSemiXMLImpl(rawTxt, StreamTagIterator(isSoff), semiXML);
}


void
StandOffManager::writeSemiXML(std::istream& rawTxt, std::ostream& semiXML)
{
    writeSemiXMLImpl(rawTxt, SequenceTagIterator<std::vector<TagData> >(tagsData.begin(), tagsData.end()), semiXML);
}

////////////////////////////////////////////////////////////////////////////////
/// Import
////////////////////////////////////////////////////////////////////////////////
enum SemiXmlLexerTokenType {
    T_TEXT,
    T_TAG,  /// everything enclosed in '<' and '>', excluding the enclosing <>
    T_EOF,
};

class SemiXmlLexer {
public:
    SemiXmlLexer(std::istream &ist)
        : _ist(ist)
        , _eof(false)
    {
        if (! ist.get(_lookahead)) {
            _eof = true;
        }
        advance();
    }

    void advance(void)
    {
        if (_eof) {
            _tokenType = T_EOF;
            return;
        }

        if (_lookahead == '<') { /// tag

            _tokenType = T_TAG;

            _currToken.clear();
            while (true) {

                char ch;
                if (! _ist.get(ch)) {
                    throw std::runtime_error(
                        "input semi-xml terminates inside a tag");
                }

                if (ch == '>') {
                    break;
                }
                else {
                    _currToken += ch;
                }
            }

            if (! _ist.get(_lookahead)) {
                _eof = true;
            }
        }
        else { /// text
            
            // XXX: a character reference across the boundary of chunk causes error
            // const unsigned int MAX_CHUNK_SIZE = 4096;

            _tokenType = T_TEXT;

            _currToken = std::string(1, _lookahead);

            while (true) {

                char ch = 0;
                if (! _ist.get(ch)) {
                    _eof = true;
                    break;
                }

                // if (_currToken.size() == MAX_CHUNK_SIZE) {
                //    _lookahead = ch;
                //    break;
                // }
                // else 
                if (ch == '<') {
                    _lookahead = ch;
                    break;
                }
                else {
                    _currToken += ch;
                }
            }
        }
    }

    SemiXmlLexerTokenType getTokenType(void) const { return _tokenType; }

    void getToken(std::string &token) const { token = _currToken; }

    /// Bad interface: Be careful!
    const std::string &getToken(void) const { return _currToken; }

private:
    std::istream &_ist;
    bool _eof;
    char _lookahead;
    std::string _currToken;
    SemiXmlLexerTokenType _tokenType;
};

void
StandOffManager::readSemiXMLandWriteRawText(
    std::istream& inSxml,
    std::ostream& outTxt
) {
    /// This value is used until the end position is determined for a tag
    const unsigned int DUMMY_END_POSITION
        = std::numeric_limits<unsigned int>::max();

    SemiXmlLexer lexer(inSxml);

    /// Seek to the first element
    while (lexer.getTokenType() != T_EOF) {
        
        if (lexer.getTokenType() == T_TAG) {
            
            const std::string &tag = lexer.getToken();

            if (tag.empty()) {
                throw std::runtime_error("empty tag");
            }

            if (tag[0] != '!' && tag[0] != '?') {
                /// neither "<!..." nor "<?..."
                break;
            }
        }

        /// any text before the first (root) tag is ignored
        lexer.advance();
    }

    if (lexer.getTokenType() == T_EOF) { /// empty document: exception?
        return; 
    }


    unsigned int currOffset = 0;
    std::map<std::string, std::stack<unsigned> > tagStacks;

    for ( ; lexer.getTokenType() != T_EOF; lexer.advance()) {

        if (lexer.getTokenType() == T_TEXT) {
            
            const std::string &text = lexer.getToken();
            std::string::const_iterator ch = text.begin();
            std::string::const_iterator end = text.end();

            while (ch != end) {
                
                if (*ch == '&') {
                    /// ch will point the next position of the terminating ';'
                    std::string unesc = convertEscapeChar(++ch, end);
                    outTxt << unesc;
                    currOffset += unesc.size();
                }
                else {
                    outTxt << *ch;
                    ++ch;
                    ++currOffset;
                }
            }
        }
        else {
            
            const std::string &tag = lexer.getToken();

            if (tag.empty() || std::isspace(tag[0])) {
                throw std::runtime_error("Badly formatted tag: <" + tag + ">");
            }

            /// tag may contain more than one spaces in its begging, but we 
            /// do not check it (it does not comform to the XML specification)

            if (tag[0] == '/') { /// End tag

                /// strip off trailing spaces; tag[0] works as the sentinel
                unsigned last = tag.size() - 1;
                while (std::isspace(tag[last])) {
                    --last;
                }

                if (last == 0) {
                    throw std::runtime_error("empty name in an end tag");
                }

                /// the region of the tag name in 'tag' is [1,last],
                /// hence its length == last
                std::string name = tag.substr(1, last);

                /// Set the end position of corresponding start tag
                std::stack<unsigned> &stack = tagStacks[name];
                if (stack.empty()) {
                    throw std::runtime_error("start/end tags do not match");
                }

                unsigned ix = stack.top();
                stack.pop();

                TagData &t = tagsData[ix];
                t.setSpan(t.getSpan().first, currOffset);

                if (ix == 0) { /// Root element is now closed
                    lexer.advance();
                    break;
                }
            }
            else if (*tag.rbegin() == '/') { /// Empty tag

                TagData td;
                if (! td.parseTag(tag.substr(0, tag.size() - 1))) {
                    throw std::runtime_error(
                        "Badly formatted tag: <" + tag + ">");
                }

                td.setSpan(currOffset, currOffset);

                tagsData.push_back(td);
            }
            else { /// Start tag
                TagData td;
                if (! td.parseTag(tag)) {
                    throw std::runtime_error(
                        "Badly formatted tag: <" + tag + ">");
                }

                td.setSpan(currOffset, DUMMY_END_POSITION);

                unsigned ix = tagsData.size();
                tagsData.push_back(td);

                /// Store the index of the new start tag to
                /// set its end position later
                tagStacks[td.getName()].push(ix);
            }
        }
    }

    /// Check if there will be no more tags
    while (lexer.getTokenType() != T_EOF) {
        if (lexer.getTokenType() == T_TAG) {
            throw std::runtime_error("input semi-XML has no root tags");
        }

        /// All the text after the end-root tag is thrown away
        lexer.advance();
    }

    /// Check if all the tags are closed
    typedef std::map<std::string, std::stack<unsigned int> > Stacks;
    typedef Stacks::const_iterator StackItr;
    for (StackItr it = tagStacks.begin(); it != tagStacks.end(); ++it) {
        if (! it->second.empty()) {
            throw std::runtime_error("too many start tags");
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
/// Read TagOrder
////////////////////////////////////////////////////////////////////////////////
void
StandOffManager::readTagOrder(const std::string &filename)
{
    std::ifstream ifs(filename.c_str());
	checkFile(ifs, filename);
    readTagOrder(ifs);
}

void
StandOffManager::readTagOrder(std::istream &is)
{
	tagOrder.clear();
	tagOrder.insert(
		tagOrder.end(),
		std::istream_iterator<std::string>(is),
		std::istream_iterator<std::string>());
}

////////////////////////////////////////////////////////////////////////////////
/// Read Standoff file
////////////////////////////////////////////////////////////////////////////////
void
StandOffManager::readDataStrictly(std::istream &is)
{
    AIsLessThanB less(tagOrder);
    TagStream tst(is);

    TagData tag;
    while (tst >> tag) {

        if (! tagsData.empty() && less(tag, tagsData.back())) {
            unsigned line = tst.getLineNumber();
            std::ostringstream msg;
			msg << "tag order is inverted between line ("
                << (line - 1) << ", " << line << ")" << std::endl;
            throw std::runtime_error(msg.str());
        }

        tagsData.push_back(tag);
    }
}

void
StandOffManager::readData(const std::string &filename)
{
    std::ifstream ifs(filename.c_str());
	checkFile(ifs, filename);
    readData(ifs);
}

void
StandOffManager::readData(std::istream& is)
{
    TagStream tst(is);

    TagData tag;
    while (tst >> tag) {
        tagsData.push_back(tag);
    }
}

////////////////////////////////////////////////////////////////////////////////
/// Write Standoff file
////////////////////////////////////////////////////////////////////////////////
void
StandOffManager::writeData(const std::string &filename)
{
    std::ofstream ofs(filename.c_str());
    checkFile(ofs, filename);
    writeData(ofs);
}

void
StandOffManager::writeData(std::ostream &os)
{
	typedef std::vector<TagData>::const_iterator TagItr;

	for (TagItr it = tagsData.begin(); it != tagsData.end(); ++it) {
		it->writeStandOffLine(os);
	}
}

////////////////////////////////////////////////////////////////////////////////
/// Concatenation and sort
////////////////////////////////////////////////////////////////////////////////
void
StandOffManager::integrateFiles(
	const std::string &filename1,
	const std::string &filename2
) {
    readData(filename1);
    readData(filename2);
    sort();
}

////////////////////////////////////////////////////////////////////////////////
/// Clip operation
////////////////////////////////////////////////////////////////////////////////
void
StandOffManager::clipData(
	const std::string &standoffFile1,
	const std::string &txtFile1,
	const std::string &tagFile,
	const std::string &standoffFile2,
	const std::string &txtFile2
) {
    std::ifstream ifsSoff(standoffFile1.c_str());
    std::ifstream ifsTxt(txtFile1.c_str());
    std::ifstream ifsTag(tagFile.c_str());
    std::ofstream ofsSoff(standoffFile2.c_str());
    std::ofstream ofsTxt(txtFile2.c_str());

    checkFile(ifsSoff, standoffFile1);
    checkFile(ifsTxt, txtFile1);
    checkFile(ifsTag, tagFile);
    checkFile(ofsSoff, standoffFile2);
    checkFile(ofsTxt, txtFile2);

    clipData(ifsSoff, ifsTxt, ifsTag, ofsSoff, ofsTxt);
}

void
copy(std::istream &ist, std::ostream &ost, unsigned length)
{
	if (length == 0) { /// minor optimization
		return;
	}

	std::vector<char> buf(length);
	if (! ist.read(&buf[0], length)) {
		throw std::runtime_error("Annotation out of range");
	}

	if (! ost.write(&buf[0], length)) {
		throw std::runtime_error("Cannot write text data");
	}
}

/// TODO: match the description in the documentiaon
///        -> modification of the sentence splitter and/or the pre-prcessing
///           procedure will be necessary
///        -> note also you need to modify the functions for unite operation 
///           when modify this function
void
StandOffManager::clipData(
	std::istream &isSoff,
	std::istream &isTxt,
	std::istream &isTag,
	std::ostream &osSoff,
	std::ostream &osTxt
) {
	std::set<std::string> relayTags;
	relayTags.insert(
		std::istream_iterator<std::string>(isTag),
		std::istream_iterator<std::string>());

	bool firstRegion = true;
	unsigned int endOfLastRegion = 0;

    TagData tag;
    TagStream tst(isSoff);
    while (tst >> tag) {

		TagData::Span span = tag.getSpan();

		if (relayTags.find(tag.getName()) == relayTags.end()) {
			continue;
		}

		if (span.second <= endOfLastRegion) {
			/// This tag region was already written
			continue;
		}

		if (endOfLastRegion < span.first) {
			/// endOfLastRegion < span.first <= span.second
			/// --> start of another contiguous text region

			if (firstRegion) {
				firstRegion = false;
			}
			else {
				/// TOO DIRTY: we should add delimiters to the input xml text,
				/// clip the delimiter and the text, and remove the
				/// delimiters after the annotation
				osTxt << '\n';
			}

			isTxt.seekg(span.first, std::ios::beg);
			copy(isTxt, osTxt, span.second - span.first);
		}
		else {
			/// span.first <= endOfLastRegion < span.second
			isTxt.seekg(endOfLastRegion, std::ios::beg);
			copy(isTxt, osTxt, span.second - endOfLastRegion);
		}

		endOfLastRegion = span.second;

		/// The document (and the older version of som) says we should
		/// emit all the tags inside the clipped region
		tag.writeStandOffLine(osSoff);
	}
}

void
StandOffManager::readConformedPositions(
	const std::string &strictFile,
	const std::string &partialFile
) {
    std::ifstream ifsSoffStrict(strictFile.c_str());
	checkFile(ifsSoffStrict, strictFile);

    std::ifstream ifsSoffPartial(partialFile.c_str());
	checkFile(ifsSoffPartial, partialFile);

    readConformedPositions(ifsSoffStrict, ifsSoffPartial);
}

void
StandOffManager::readConformedPositions(
	std::istream &isSoffStrict,
	std::istream &isSoffPartial
) {
    Mapper mapper;

    try {
	    TagData tag;
        TagStream tst(isSoffStrict);
        while (tst >> tag) {
            mapper.setClippingSpan(tag.getSpan());
        }
    }
    catch (const StandOffFormatError &e) {
        throw std::runtime_error(
            std::string("container standoff: ") + e.what());
    }

	Mapper::SearchRegion emptyTagRegion = mapper.getInitialSearchRegion();

    try {
        TagData tag;
        TagStream tst(isSoffPartial);
        while (tst >> tag) {
            TagData::Span mapped;
            emptyTagRegion = mapper.map(emptyTagRegion, tag.getSpan(), mapped);
            tag.setSpan(mapped);
            tagsData.push_back(tag);
        }
    }
    catch (const StandOffFormatError &e) {
        throw std::runtime_error(
            std::string("embedded standoff: ") + e.what());
    }
}

void
StandOffManager::readConformedPositions(
	std::istream &isSoffStrict,
	std::istream &isSoffPartial,
    std::ostream &out
) {
    Mapper mapper;

    try {
	    TagData tag;
        TagStream tst(isSoffStrict);
        while (tst >> tag) {
            mapper.setClippingSpan(tag.getSpan());
        }
    }
    catch (const StandOffFormatError &e) {
        throw std::runtime_error(
            std::string("container standoff: ") + e.what());
    }

	Mapper::SearchRegion emptyTagRegion = mapper.getInitialSearchRegion();

    try {
        TagData tag;
        TagStream tst(isSoffPartial);
        while (tst >> tag) {
            TagData::Span mapped;
            emptyTagRegion = mapper.map(emptyTagRegion, tag.getSpan(), mapped);
            tag.setSpan(mapped);
            tag.writeStandOffLine(out);
        }
    }
    catch (const StandOffFormatError &e) {
        throw std::runtime_error(
            std::string("embedded standoff: ") + e.what());
    }
}

////////////////////////////////////////////////////////////////////////////////
/// Merge operation
////////////////////////////////////////////////////////////////////////////////
StandOffManager&
StandOffManager::operator+= (const StandOffManager &a)
{
	typedef std::vector<TagData>::const_iterator TagItr;

	AIsLessThanB less(tagOrder);

    std::vector<TagData> tmpTagsData;
    std::vector<TagData> data;
	a.getData(data);

    TagItr iter2 = tagsData.begin(); /// iter2: self (file1)
    for (TagItr iter = data.begin(); iter != data.end(); ++iter) {
		/// iter: the other (file2)

        while (iter2 != tagsData.end()
				&& iter2->getSpan().first < iter->getSpan().first) {

            tmpTagsData.push_back(*iter2);
            ++iter2;
        }

        while (iter2 != tagsData.end()
				&& iter2->getSpan().first == iter->getSpan().first) {

            if (iter2->getSpan().second > iter->getSpan().second){
                tmpTagsData.push_back(*iter2);
                ++iter2;
            }
            else if (iter2->getSpan().second == iter->getSpan().second) {

				if (less.compare3way(iter->getName(), iter2->getName()) >= 0) {
					/// When they have the same order, let the tag from file2 
					/// precede the other
					break;
				}
				else {
                	tmpTagsData.push_back(*iter2);
                	++iter2;
				}
            }
            else {
                break;
            }
        }

        tmpTagsData.push_back(*iter);
    }

	/// Append all the rest of tagsData
	tmpTagsData.insert(
		tmpTagsData.end(), iter2, static_cast<TagItr>(tagsData.end()));

	tagsData.swap(tmpTagsData);

    return *this;
}
