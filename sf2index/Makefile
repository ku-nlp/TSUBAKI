ID = 000000
IDX0_SUFFIX = idx0
IDX1_SUFFIX = idx1
BASEDIR = $(shell pwd)
XMLS = $(wildcard $(BASEDIR)/*.xml)
IDXS = $(patsubst %.xml,%.$(IDX0_SUFFIX),$(XMLS))
MERGED_IDX = $(BASEDIR)/$(ID).$(IDX1_SUFFIX)
MERGED_IDX_FINAL = $(BASEDIR)/$(ID).idx
MERGED_IDX_DF = $(BASEDIR)/$(ID).idx.df
MAPFILE = $(BASEDIR)/sid2tid
XMLFILES = $(ID).xmls
URL_TITLE_TXT = $(ID).url_title
URLDB = $(BASEDIR)/$(ID).url.cdb
TITLEDB = $(BASEDIR)/$(ID).title.cdb

UtilsDir = ../../Utils

all: idx_bin idx_length dfdb

$(IDXS): $(BASEDIR)/%.$(IDX0_SUFFIX) : $(BASEDIR)/%.xml
	perl $(BASEDIR)/sf2term.pl -suffix $(IDX0_SUFFIX) $< > $@

$(MERGED_IDX): $(IDXS)
	perl $(BASEDIR)/../scripts/merge_idx.pl -dir $(BASEDIR) -suffix $(IDX0_SUFFIX) > $@

$(MERGED_IDX_FINAL): $(MERGED_IDX) $(MAPFILE)
	perl $(BASEDIR)/../scripts/merge_sorted_idx.pl -dir $(BASEDIR) -suffix $(IDX1_SUFFIX) -mapfile $(MAPFILE) > $@

idx_bin: $(MERGED_IDX_FINAL)
	perl -I $(UtilsDir)/perl -I $(BASEDIR)/../scripts $(BASEDIR)/../scripts/binarize_idx.pl -syn $<

idx_length: $(MERGED_IDX_FINAL)
	perl $(BASEDIR)/../scripts/make-dlength-db.perl -txt $<

$(MERGED_IDX_DF): $(MERGED_IDX)
	perl $(BASEDIR)/../scripts/idx2df.pl $<

dfdb: $(MERGED_IDX_FINAL)
	perl -I $(UtilsDir)/perl $(BASEDIR)/../scripts/make-df-db.perl < $<

$(MAPFILE): $(MERGED_IDX)
	perl $(BASEDIR)/../scripts/make-mapfile.perl $(MERGED_IDX) > $@

$(XMLFILES): $(XMLS)
	ls $< > $@

$(URL_TITLE_TXT): $(XMLFILES)
	perl $(BASEDIR)/../scripts/extract-url-title.perl -files $(XMLFILES) > $(URL_TITLE_TXT)

clean:
	rm -f $(IDXS) $(MERGED_IDX) $(MERGED_IDX_FINAL) $(MAPFILE) idx*.word.dat* idx*.dpnd.dat* offset*.word*.cdb* offset*.dpnd*.cdb* *.doc_length.* df.word.* df.dpnd.*
