XMLS = *.xml
IDX = 000.idx

UtilsDir = ../../Utils

all: idx_bin idx_length

$(IDX): $(XMLS)
	cat $< | perl ../scripts/convert_sf2term.pl > $@

idx_bin: $(IDX)
	perl -I $(UtilsDir)/perl -I ../scripts ../scripts/binarize_idx.pl $<

idx_length: $(IDX)
	perl ../scripts/make-dlength-db.perl $<

clean:
	rm -f $(IDX) idx*.word.dat idx*.dpnd.dat offset*.word.cdb offset*.dpnd.cdb *.doc_length.bin
