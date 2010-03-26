#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include "cdb.h"
#include <iostream.h>

using std::cout;
using std::cerr;
using std::endl;

extern "C" int cdb_init(struct cdb *cdbp, int fd);
extern "C" int cdb_find(struct cdb *cdbp, const void *key, unsigned klen);
extern "C" int cdb_read(const struct cdb *cdbp, void *buf, unsigned len, unsigned pos);

int main (int argc, char **argv) {

  int fd;
  struct cdb *_cdb = (cdb*)malloc(sizeof(cdb));
  if (!_cdb) {
     fprintf(stderr, "Can't allocate memory.\n");
	exit(-1);
    }


  char *key, *val;
  key = argv[2];
  unsigned klen, vlen, vpos;

  klen = sizeof(key);
  if ((fd = open (argv[1], O_RDONLY)) < 0) {
    cout << "error" << endl;
  }

  cdb_init(_cdb, fd);
  if (cdb_find(_cdb, key, strlen(key)) > 0) {
    vpos = cdb_datapos(_cdb);
    vlen = cdb_datalen(_cdb);
    val = (char*)malloc(vlen + 1);
    cdb_read(_cdb, val, vlen, vpos);
    cout << key << " " << val << endl;
  } else {
    cout << key << " " << klen << endl;
  }

  return 0;
}
