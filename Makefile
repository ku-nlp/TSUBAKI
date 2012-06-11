CLEANFILES = conf/configure conf/tsubaki.conf sf2index/Makefile search.sh cgi/index.cgi cgi/api.cgi

all:
	$(MAKE) -C search
	$(MAKE) -C enju2tsubaki/StandOffManager

html2sf:
	$(MAKE) -C sf2index html2sf

indexing:
	$(MAKE) -C sf2index indexing

clean:
	$(MAKE) -C search clean
	$(MAKE) -C sf2index clean
	rm -f $(CLEANFILES)
