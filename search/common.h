#ifndef COMMON_H
#define COMMON_H

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <ext/hash_map>
#include <set>
#include <algorithm>
#include <cstdlib>
#include <ios>
#include <iomanip>
#include <stdlib.h>
#include <math.h>
#include "lisp.h"
#include "cdb.h"

enum documents_type {
    DOCUMENTS_ROOT, 
    DOCUMENTS_AND, 
    DOCUMENTS_OR, 
    DOCUMENTS_TERM_STRICT, 
    DOCUMENTS_TERM_LENIENT, 
    DOCUMENTS_TERM_OPTIONAL, 
};
typedef enum documents_type documents_type;

// bool sort_by_term_pos(const std::vector<int> *left, const std::vector<int> *right) {
//    return left->front() < right->front();
// }

inline int intchar2int(unsigned char *cp) {
    return *cp + 
	(*(cp + 1) << 8) + 
	(*(cp + 2) << 16) + 
	(*(cp + 3) << 24);
}

inline int twochar2int(unsigned char *cp) {
    return *cp + 
	(*(cp + 1) << 8);
}

// split function with split_num
template<class T>
inline int split_string(const std::string &src, const std::string &key, T &result, int split_num)
{
    result.clear();
    int len =  src.size();
    int i = 0, si = 0, count = 0;

    while(i < len) {
	while (i < len && key.find(src[i]) != std::string::npos) { si++; i++; } // skip beginning spaces
	while (i < len && key.find(src[i]) == std::string::npos) i++; // skip contents
	if (split_num && ++count >= split_num) { // reached the specified num
	    result.push_back(src.substr(si, len - si)); // push the remainder string
	    break;
	}
	result.push_back(src.substr(si, i - si));
	si = i;
    }

    return result.size();
}

// split function
template<class T>
inline int split_string(const std::string &src, const std::string &key, T &result)
{
    return split_string(src, key, result, 0);
}

// join function
inline std::string join_string(const std::vector<std::string> &str, const std::string &key)
{
    std::string dst;

    for (std::vector<std::string>::const_iterator i = str.begin(); i != str.end(); i++) {
        if (i == str.begin()) {
            dst += *i;
        }
        else {
            dst += key + *i;
        }
    }
    return dst;
}

inline bool is_blank_line(const std::string &str)
{
    for (std::string::size_type i = 0; i < str.size(); i++) {
	if (str[i] == '\n' || 
	    str[i] == '\r' || 
	    str[i] == ' ' || // space
	    str[i] == '	') { // tab
	    ;
	}
	else {
	    return 0;
	}
    }

    return 1;
}

extern "C" int atoi(const char *);
extern "C" long long atoll(const char *);
extern "C" double atof(const char *);

inline int atoi(const std::string &str) {
    return atoi(str.c_str());
}

inline long long atoll(const std::string &str) {
    return atoll(str.c_str());
}

inline double atof(const std::string &str) {
    return atof(str.c_str());
}

// int to string
template<class T>
inline std::string int2string(const T i)
{
    std::ostringstream o;

    o << i;
    return o.str();

    /*
    string ret;
    try {
        ret = boost::lexical_cast<string>(i);
    }
    catch (boost::bad_lexical_cast &e) {
        cerr << "Bad cast: " << e.what() << endl;
    }
    return ret;
    */
}

// Convert an integer to its string representation.
// std::string int2str(int i) {
//     std::stringstream ss;
//     ss << std::setfill('0') << std::setw(6) << i;
//    return ss.str();
// }

// from lisp.c
extern "C" int s_feof(FILE *fp);
extern "C" CELL *s_read(FILE *fp);
extern "C" CELL *s_read_from_string(char **chp);
extern "C" CELL *car(CELL *cell);
extern "C" CELL *cdr(CELL *cell);
extern "C" CELL *cons(void *car, void *cdr);
extern "C" int length(CELL *list);
extern "C" void error_in_lisp(void);
extern "C" void *my_alloc(int n);

// from cdb.h
extern "C" int cdb_init(struct cdb *cdbp, int fd);
extern "C" int cdb_find(struct cdb *cdbp, const void *key, unsigned klen);
extern "C" int cdb_read(const struct cdb *cdbp, void *buf, unsigned len, unsigned pos);

#endif
