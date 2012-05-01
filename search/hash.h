#ifndef HASH_H
#define HASH_H

#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

using std::string;
using std::cout;
using std::cerr;
using std::endl;

double gettimeofday_sec();

class Dbm {
    bool available;
    string dbname;
    string hostname;
    bool defined_keymap;
    bool IS_32BIT_CPU_MODE;
    std::vector< std::pair<string, cdb*> > k2db;
    std::vector< std::pair<string, string> > k2dbfile;
    int fd;
    struct cdb *_cdb;

  public:
    Dbm() {
	defined_keymap = false;
	available = false;

#ifdef _32BIT_CPU_MODE_FLAG
	IS_32BIT_CPU_MODE = true;
#else
	IS_32BIT_CPU_MODE = false;
#endif
    }

    Dbm(string &in_dbname) {
	init(in_dbname, "none");
    }

    Dbm(string &in_dbname, string _hostname) {
	init(in_dbname, _hostname);
    }

    bool init(string &in_dbname, string _hostname) {
	hostname = _hostname;
	available = true;
	if (in_dbname.find("keymap") != string::npos) {
	    defined_keymap = true;

#ifdef _32BIT_CPU_MODE_FLAG
	    IS_32BIT_CPU_MODE = true;
#else
	    IS_32BIT_CPU_MODE = false;
#endif

	    unsigned int loc = in_dbname.find_last_of("keymap");
	    string file0 = string(in_dbname, 0, loc - 6) + ".0";
	    if (!IS_32BIT_CPU_MODE) {
		struct cdb *_db = tieCDB(file0);
                if (_db == NULL) {
                    available = false;
                }
		k2db.push_back(std::pair<string, cdb*>("", _db));
	    } else {
		k2dbfile.push_back(std::pair<string, string>("", file0));
	    }

	    string dirname = getDirName(in_dbname);
	    std::ifstream fin(in_dbname.c_str());
	    while (!fin.eof()) {
		string key;
		string filename;
		fin >> key;
		fin >> filename;
		if (filename.find("cdb") == string::npos)
		    break;

		if (!IS_32BIT_CPU_MODE) {
		    struct cdb *_db = tieCDB(dirname + "/" + filename);
		    if (_db == NULL) {
			available = false;
		    }
		    k2db.push_back(std::pair<string, cdb*>(key, _db));
		} else {
		    k2dbfile.push_back(std::pair<string, string>(key, dirname + "/" + filename));
		}
	    }
	    fin.close();

	}
	else {
	    defined_keymap = false;
	    dbname = in_dbname;
	    _cdb = tieCDB(dbname);
	    if (_cdb == NULL) {
		available = false;
	    }
	}
	return available;
    }

    cdb* tieCDB (string dbfile) {
	struct cdb *db = (cdb*)malloc(sizeof(cdb));
	if (!db) {
	    cerr << "Can't allocate memory @ hash.h." << endl;
	    exit(-1);
	}

	double start = (double) gettimeofday_sec();
	int _fd;
	if ((_fd = open(dbfile.c_str(), O_RDONLY)) < 0) {
	    // cerr << "Can't open file: " << dbfile << endl;
	    return NULL;
	}
	int ret = cdb_init(db, _fd);

	double end = (double) gettimeofday_sec();

	if (ret < 0) {
	    cerr << "Can't tie! " << dbfile << " " << ret << " time=" << (end - start) << " hostname=" << hostname << endl;
	} else {
	}

	return db;
    }

    string getDirName (string filepath) {
	unsigned int loc = filepath.find_last_of("/");
	string dirname = string(filepath, 0, loc);
	return dirname;
    }

    bool is_open() {
	return available;
    }

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
	    free(val);
	} else {
	    // cout << key << " is not found." << endl;
	}
	return ret_value;
    }

    string _get (string key) {
	if (IS_32BIT_CPU_MODE)
	    return _get_for_32bit_mode (key);
	
	cdb *db = k2db[0].second;
	for (std::vector<std::pair<string, cdb*> >::iterator it = k2db.begin(); it != k2db.end(); ++it) {
	    if (key < (string)(*it).first) {
		break;
	    }
	    db = (*it).second;
	}

	string ret = get ((const char*)key.c_str(), db);

	return ret;
    }

    string _get_for_32bit_mode (string key) {
	string file = k2dbfile[0].second;
	for (std::vector<std::pair<string, string> >::iterator it = k2dbfile.begin(); it != k2dbfile.end(); ++it) {
	    if (key < (string)(*it).first) {
		break;
	    }
	    file = (*it).second;
	}
        string ret;
	cdb *db = tieCDB(file);
        if (db != NULL) {
            ret = get ((const char*)key.c_str(), db);
            cdb_free(db);
        }
        return ret;
    }
};

#endif
