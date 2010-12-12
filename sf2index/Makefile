ID = 000
IDX0_SUFFIX = idx0
IDX1_SUFFIX = idx1
BASEDIR = $(shell pwd)
DATADIR = sample_data
HTMLS = $(wildcard $(DATADIR)/*.html)
XMLS = $(wildcard $(DATADIR)/*.xml)
IDXS = $(patsubst %.xml,%.$(IDX0_SUFFIX),$(XMLS))
MERGED_IDX = $(DATADIR)/$(ID).$(IDX1_SUFFIX)
MERGED_IDX_FINAL = $(DATADIR)/$(ID).idx
MERGED_IDX_DF = $(DATADIR)/$(ID).idx.df
MAPFILE = $(DATADIR)/sid2tid
XMLLIST = $(DATADIR)/$(ID).xmls
URL_TITLE_TXT = $(DATADIR)/$(ID).url_title
URLDB = $(DATADIR)/did2url.cdb
TITLEDB = $(DATADIR)/did2title.cdb

UtilsDir = ../../Utils
WWW2sfDir = ../../WWW2sf

all: idx_bin idx_length dfdb

html2xml:
	$(WWW2sfDir)/tool/www2sf.sh -x -s $(DATADIR) $(DATADIR)

$(IDXS): $(DATADIR)/%.$(IDX0_SUFFIX) : $(DATADIR)/%.xml
	perl $(BASEDIR)/sf2term.pl -suffix $(IDX0_SUFFIX) $< > $@

$(MERGED_IDX): $(IDXS)
	perl $(BASEDIR)/../scripts/merge_idx.pl -dir $(DATADIR) -suffix $(IDX0_SUFFIX) > $@

$(MERGED_IDX_FINAL): $(MERGED_IDX) $(MAPFILE)
	perl $(BASEDIR)/../scripts/merge_sorted_idx.pl -dir $(DATADIR) -suffix $(IDX1_SUFFIX) -mapfile $(MAPFILE) > $@

idx_bin: $(MERGED_IDX_FINAL)
	perl -I $(UtilsDir)/perl -I $(BASEDIR)/../scripts $(BASEDIR)/../scripts/binarize_idx.pl -syn $<

idx_length: $(MERGED_IDX_FINAL)
	perl $(BASEDIR)/../scripts/make-dlength-db.perl -txt $<

$(MERGED_IDX_DF): $(MERGED_IDX)
	perl $(BASEDIR)/../scripts/idx2df.pl $<

dfdb: $(MERGED_IDX_FINAL)
	perl -I $(UtilsDir)/perl $(BASEDIR)/../scripts/make-df-db.perl --dir $(DATADIR) < $<

$(MAPFILE): $(MERGED_IDX)
	perl $(BASEDIR)/../scripts/make-mapfile.perl $(MERGED_IDX) > $@

$(XMLLIST): $(XMLS)
	ls $(XMLS) > $@

$(URL_TITLE_TXT): $(XMLLIST)
	perl $(BASEDIR)/../scripts/extract-url-title.perl -files $(XMLLIST) > $(URL_TITLE_TXT)

url_title_db : $(URL_TITLE_TXT)
	perl $(BASEDIR)/../scripts/make-url-title-cdbs.perl --titledb $(TITLEDB) --urldb $(URLDB) $<

clean:
	rm -f $(IDXS) $(DATADIR)/*.$(IDX0_SUFFIX) $(MERGED_IDX) $(MERGED_IDX_FINAL) $(MAPFILE) $(XMLLIST) $(URL_TITLE_TXT) $(URLDB) $(TITLEDB) $(DATADIR)/idx*.word.dat* $(DATADIR)/idx*.dpnd.dat* $(DATADIR)/offset*.word*.cdb* $(DATADIR)/offset*.dpnd*.cdb* $(DATADIR)/*.doc_length.* $(DATADIR)/df.word.* $(DATADIR)/df.dpnd.*

clean_xml:
	rm -f $(XMLS)
