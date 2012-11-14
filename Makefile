CLEANFILES = conf/configure sf2index/Makefile search.sh cgi/index.cgi cgi/api.cgi

all:
	$(MAKE) -C search
	$(MAKE) -C enju2tsubaki/StandOffManager

html:
	$(MAKE) -C sf2index html

xml_simple:
	$(MAKE) -C sf2index xml_simple

xml:
	$(MAKE) -C sf2index xml

indexing:
	$(MAKE) -C sf2index

clean:
	$(MAKE) -C search clean
	$(MAKE) -C enju2tsubaki/StandOffManager clean

cleanindex:
	$(MAKE) -C sf2index clean

mostlyclean: clean indexclean
	rm -f $(CLEANFILES)
