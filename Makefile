all:
	cd search && make && cd ..

html2sf:
	cd sf2index && make html2sf && cd ..

indexing:
	cd sf2index && make && cd ..

clean:
	cd search && make clean && cd ..
	cd sf2index && make clean && cd ..
