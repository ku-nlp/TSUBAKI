CXX = g++4
# CXXFLAGS = -I lisp -g -Wall -pg -I /usr/local/include/ -I /home/skeiji/local/include/
CXXFLAGS = -I lisp -O3 -Wall -I /usr/local/include/ -I /home/skeiji/local/include/
# OBJECTS = slave_server.o hash.o
OBJECTS = slave_server.o
HEADERS = slave_server.h hash.h
MAKE_DB_OBJECTS = make_db.cc

all: slave_server make_db

slave_server: $(OBJECTS) $(HEADERS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJECTS) lisp/lisp.a /home/skeiji/local/lib/libcdb.a

make_db: $(MAKE_DB_OBJECTS)
	$(CXX) $(CXXFLAGS) -o $@ $(MAKE_DB_OBJECTS)

clean:
	rm -f $(OBJECTS) slave_server make_db
