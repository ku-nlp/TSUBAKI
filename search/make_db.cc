#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include "common.h"
#include "cdbpp.h"

#define DBNAME  "sample.cdb"

bool build(std::ifstream &ifs) {
    // Open a database file for writing (with binary mode).
    std::ofstream ofs(DBNAME, std::ios_base::binary);
    if (ofs.fail()) {
        std::cerr << "ERROR: Failed to open a database file." << std::endl;
        return false;
    }

    try {
        // Create an instance of CDB++ writer.
        cdbpp::builder dbw(ofs);

        // Insert key/value pairs to the CDB++ writer.
	std::string buffer;
	while (getline(ifs, buffer)) {
	    std::vector<std::string> line;
	    split_string(buffer, " ", line);
	    dbw.put(line[0].c_str(), line[0].length(), line[1].c_str(), line[1].length());
	}
        // Destructing the CDB++ writer flushes the database to the stream.
    } catch (const cdbpp::builder_exception& e) {
        // Abort if something went wrong...
        std::cerr << "ERROR: " << e.what() << std::endl;
        return false;
    }

    return true;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
	std::cerr << "Usage: make_db database < file" << std::endl;
	exit(1);
    }

    std::ifstream ifs(argv[1]);
    bool b = build(ifs);
    std::cout << (b ? "OK" : "FAIL") << std::endl;
    return b ? 0 : 1;
}
