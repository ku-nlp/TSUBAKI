CXX = g++
CXXFLAGS = -Ilisp -Icdb -O3 -Wall
# CXXFLAGS = -Ilisp -Icdb -O3 -Wall -D_FILE_OFFSET_BITS=64 -D_LARGEFILE64_SOURCE=1
OBJECTS = slave_server.o document.o documents.o
HEADERS = hash.h common.h term.h document.h documents.h
MAKE_DB_OBJECTS = make_db.cc
LISP_LIB = lisp/lisp.a
CDB_LIB = cdb/libcdb.a

all: slave_server make_db

slave_server: $(OBJECTS) $(HEADERS) $(LISP_LIB) $(CDB_LIB)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJECTS) $(LISP_LIB) $(CDB_LIB)

make_db: $(MAKE_DB_OBJECTS)
	$(CXX) $(CXXFLAGS) -o $@ $(MAKE_DB_OBJECTS)

slave_server.o: $(HEADERS) slave_server.cc
	$(CXX) $(CXXFLAGS) -c -o $@ slave_server.cc

$(LISP_LIB):
	cd lisp && make && cd ..

$(CDB_LIB):
	cd cdb && make && cd ..

clean:
	rm -f $(OBJECTS) slave_server make_db
	cd lisp && make clean && cd ..
