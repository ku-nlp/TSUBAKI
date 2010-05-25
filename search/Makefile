CXX = g++4
# CXXFLAGS = -I lisp -g -Wall -pg -I /usr/local/include/ -I /home/skeiji/local/include/
CXXFLAGS = -I lisp -O3 -Wall -I /usr/local/include/ -I /home/skeiji/local/include/
OBJECTS = slave_server.o
HEADERS = slave_server.h hash.h
MAKE_DB_OBJECTS = make_db.cc
LISP_LIB = lisp/lisp.a
CDB_LIB = -lcdb

all: slave_server make_db

slave_server: $(OBJECTS) $(HEADERS) $(LISP_LIB)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJECTS) $(LISP_LIB) $(CDB_LIB)

make_db: $(MAKE_DB_OBJECTS)
	$(CXX) $(CXXFLAGS) -o $@ $(MAKE_DB_OBJECTS)

slave_server.o: $(HEADERS) slave_server.cc
	$(CXX) $(CXXFLAGS) -c -o $@ slave_server.cc

$(LISP_LIB):
	cd lisp && make && cd ..

clean:
	rm -f $(OBJECTS) slave_server make_db
	cd lisp && make clean && cd ..
