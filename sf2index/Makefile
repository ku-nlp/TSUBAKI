IDX_SUFFIX = idx0
XMLS = *.xml
IDXS = $(patsubst %.xml,%.$(IDX_SUFFIX),$(wildcard *.xml))
MERGED_IDX = 000.idx

UtilsDir = ../../Utils

all: idx_bin idx_length

$(IDXS): $(XMLS)
	perl ./sf2term.pl -suffix $(IDX_SUFFIX) $(XMLS)

$(MERGED_IDX): $(IDXS)
	perl ../scripts/merge_idx.pl -dir . -suffix $(IDX_SUFFIX) > $@

idx_bin: $(MERGED_IDX)
	perl -I $(UtilsDir)/perl -I ../scripts ../scripts/binarize_idx.pl -syn -legacy_mode $<

idx_length: $(MERGED_IDX)
	perl ../scripts/make-dlength-db.perl $<

clean:
	rm -f $(IDXS) $(MERGED_IDX) idx*.word.dat* idx*.dpnd.dat* offset*.word*.cdb* offset*.dpnd*.cdb* *.doc_length.bin
