#ifndef HASH_H
#define HASH_H

#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
// #include "cdbpp.h"

using std::string;
using std::cout;
using std::cerr;
using std::endl;

class Dbm {
    bool available;
    string dbname;
    struct cdb *_cdb;
    int fd;
    // cdbpp::cdbpp *db;
  public:
    /*
    Dbm(const string &in_dbname) {
	dbname = in_dbname;
	open();
    }
    Dbm(const char *in_dbname) {
	dbname = in_dbname;
	open();
    }
    */
    Dbm() {
	;
    }

    Dbm(const string &in_dbname) {
	dbname = in_dbname;
	_cdb = (cdb*)malloc(sizeof(cdb));
	if (!_cdb) {
	    cerr << "Can't allocate memory @ hash.h." << endl;
	    exit(-1);
	}
	
	if ((fd = open(in_dbname.c_str(), O_RDONLY)) < 0) {
	    cerr << "Can't open file: " << in_dbname << endl;
	}
	cdb_init(_cdb, fd);
    }

    Dbm(char *in_dbname) {
	dbname = in_dbname;
	_cdb = (cdb*)malloc(sizeof(cdb));
	if (!_cdb) {
	    cerr << "Can't allocate memory @ hash.h." << endl;
	    exit(-1);
	}
	
	if ((fd = open(in_dbname, O_RDONLY)) < 0) {
	    cerr << "Can't open file: " << in_dbname << endl;
	}
	cdb_init(_cdb, fd);
    }





/*
    bool open(const string &in_dbname) {
	dbname = in_dbname;
	return open();
    }


    bool Dbm::open() {
	available = true;
	return available;
    }


*/

/*
    bool Dbm::open() {
	// Open the database file for reading (with binary mode)
	std::ifstream ifs(dbname.c_str(), std::ios_base::binary);
	if (ifs.fail()) {
	    cerr << "ERROR: Failed to open a database file for reading." << endl;
	    available = false;
	    return false;
	}

	try {
	    // Open the database from the input stream
	    db = new cdbpp::cdbpp(ifs);
	    if (!db->is_open()) {
		cerr << "ERROR: Failed to read a database file." << endl;
		available = false;
	    }
	} catch (const cdbpp::cdbpp_exception& e) {
	    // Abort if something went wrong...
	    cerr << "ERROR: " << e.what() << endl;
	    available = false;
	}
	available = true;
	return available;
    }
*/

    bool is_open() {
	return available;
    }

/*
    string Dbm::get(const string &key) {
	size_t vsize;
	string ret_value;
	const char *value = (const char *)db->get(key.c_str(), key.length(), &vsize);
	if (value == NULL) {
	    // cerr << "ERROR: The key <" << key << "> is not found." << endl;
	}
	else {
	    ret_value = value;
	    // cerr << "FOUND: The key <" << key << "> is found: " << ret_value << endl;
	}
	return ret_value;
    }
*/

    string get(const string &key) {
	return get(key.c_str());
    }

    string get(const char *key) {
	string ret_value;
	unsigned vlen, vpos;
	if (cdb_find(_cdb, key, strlen(key)) > 0) {
	    vpos = cdb_datapos(_cdb);
	    vlen = cdb_datalen(_cdb);
	    // for \0
	    char *val = (char*)malloc(vlen + 1);
	    cdb_read(_cdb, val, vlen, vpos);
	    *(val + vlen) = '\0';
	    // cout << key << " is found. val = " << val << endl;
	    ret_value = val;
	} else {
	    // cout << key << " is not found." << endl;
	}
	return ret_value;
    }
};

#endif
