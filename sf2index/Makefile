IDX_SUFFIX = idx0
BASEDIR = $(shell pwd)
XMLS = $(wildcard $(BASEDIR)/*.xml)
IDXS = $(patsubst %.xml,%.$(IDX_SUFFIX),$(XMLS))
MERGED_IDX = $(BASEDIR)/000.idx

UtilsDir = ../../Utils

all: idx_bin idx_length

$(IDXS): $(BASEDIR)/%.$(IDX_SUFFIX) : $(BASEDIR)/%.xml
	perl $(BASEDIR)/sf2term.pl -suffix $(IDX_SUFFIX) $< > $@

$(MERGED_IDX): $(IDXS)
	perl $(BASEDIR)/../scripts/merge_idx.pl -dir $(BASEDIR) -suffix $(IDX_SUFFIX) > $@

idx_bin: $(MERGED_IDX)
	perl -I $(UtilsDir)/perl -I $(BASEDIR)/../scripts $(BASEDIR)/../scripts/binarize_idx.pl -syn -legacy_mode $<

idx_length: $(MERGED_IDX)
	perl $(BASEDIR)/../scripts/make-dlength-db.perl $<

clean:
	rm -f $(IDXS) $(MERGED_IDX) idx*.word.dat* idx*.dpnd.dat* offset*.word*.cdb* offset*.dpnd*.cdb* *.doc_length.bin
