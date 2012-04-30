all:
	cd search && make && cd ..

indexing:
	cd sf2index && make && cd ..

clean:
	cd search && make clean && cd ..
	cd sf2index && make clean && cd ..
