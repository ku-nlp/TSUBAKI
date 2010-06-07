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
    bool defined_keymap;
    struct cdb *_cdb;
    std::vector< std::pair<string, cdb*> > k2db;
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
	defined_keymap = false;
	;
    }

    Dbm(string &in_dbname) {
	if (in_dbname.find("keymap") != string::npos) {
	    defined_keymap = true;
	    unsigned int loc = in_dbname.find_last_of("keymap");
	    string file0 = string(in_dbname, 0, loc - 6) + ".0";
	    struct cdb *_db = tieCDB(file0);
	    k2db.push_back(std::pair<string, cdb*>("", _db));

	    string dirname = getDirName(in_dbname);
	    std::ifstream fin(in_dbname.c_str());
	    while (!fin.eof()) {
		string key;
		string filename;
		fin >> key;
		fin >> filename;
		if (filename.find("cdb") == string::npos)
		    break;

		struct cdb *_db = tieCDB(dirname + "/" + filename);
		k2db.push_back(std::pair<string, cdb*>(key, _db));
	    }
	    fin.close();

	}
	else {
	    defined_keymap = false;
	    dbname = in_dbname;
	    _cdb = tieCDB(dbname);
	}
    }

    cdb* tieCDB (string dbfile) {
	struct cdb *db = (cdb*)malloc(sizeof(cdb));
	if (!db) {
	    cerr << "Can't allocate memory @ hash.h." << endl;
	    exit(-1);
	}

	int _fd;
	if ((_fd = open(dbfile.c_str(), O_RDONLY)) < 0) {
	    cerr << "Can't open file: " << dbfile << endl;
	}
	cdb_init(db, _fd);

	return db;
    }

    string getDirName (string filepath) {
	unsigned int loc = filepath.find_last_of("/");
	string dirname = string(filepath, 0, loc);
	return dirname;
    }

/*
    Dbm(char *in_dbname) {
	std::string _file = in_dbname;
	Dbm(_file);
    }
*/




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

    string get (string key) {
	if (defined_keymap) {
	    return _get(key);
	} else {
	    return get((const char*)key.c_str(), _cdb);
	}
    }

    string get (const char *key) {
	if (defined_keymap) {
	    const string k = key;
	    return _get(k);
	} else {
	    return get(key, _cdb);
	}
    }

    string get (const char *key, cdb* db) {
	string ret_value;
	unsigned vlen, vpos;
	if (cdb_find(db, key, strlen(key)) > 0) {
	    vpos = cdb_datapos(db);
	    vlen = cdb_datalen(db);
	    // for \0
	    char *val = (char*)malloc(vlen + 1);
	    cdb_read(db, val, vlen, vpos);
	    *(val + vlen) = '\0';
	    // cout << key << " is found. val = " << val << endl;
	    ret_value = val;
	} else {
	    // cout << key << " is not found." << endl;
	}
	return ret_value;
    }

    string _get (string key) {
	cdb *db = k2db[0].second;
	for (std::vector<std::pair<string, cdb*> >::iterator it = k2db.begin(); it != k2db.end(); ++it) {
	    if (key < (string)(*it).first) {
		break;
	    }
	    db = (*it).second;
	}

	return get ((const char*)key.c_str(), db);
    }

};

#endif
