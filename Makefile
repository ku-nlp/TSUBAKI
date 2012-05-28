CLEANFILES = conf/configure conf/tsubaki.conf sf2index/Makefile search.sh cgi/index.cgi cgi/api.cgi

all:
	make -C search

html2sf:
	make -C sf2index html2sf

indexing:
	make -C sf2index indexing

clean:
	make -C search clean
	make -C sf2index clean
	rm -f $(CLEANFILES)
