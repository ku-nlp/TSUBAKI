#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include "hash.h"
#include <iostream.h>

using std::cout;
using std::cerr;
using std::endl;

extern "C" int cdb_init(struct cdb *cdbp, int fd);
extern "C" int cdb_find(struct cdb *cdbp, const void *key, unsigned klen);
extern "C" int cdb_read(const struct cdb *cdbp, void *buf, unsigned len, unsigned pos);

int main (int argc, char **argv) {

    Dbm *db = new Dbm(argv[1]);
    for (int i = 2; i < argc; i++) {
	std::string value = db->get(argv[i]);
	cout << value << endl;
    }
    return 0;
}
