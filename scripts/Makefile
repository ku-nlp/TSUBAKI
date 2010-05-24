# $Id$

SHELL = sh
CONFIG = ${HOME}/cvs/SearchEngine/conf/indexing.conf
SFLIST = flist
SCHEME = -syn
IPSJ = ""
format = %03d
mapfile = ${HOME}/ipsj/data3/org/fid2did

include $(CONFIG)


# インデックスデータの出力先
DIST_HOST_OF_IDX = $(dist_host_of_idx)
DIST_DIR_OF_IDX  = $(dist_dir_of_idx)

host_file = hosts
access_method = ssh


start: init mk_taskfile_for_mkidx run_taskfile_for_mkidx mk_taskfile_for_mgidx run_taskfile_for_mgidx run_mkdfdb


init: connect_node
	gxpc e mkdir -p $(workspace_prefix) 2> /dev/null
	gxpc quit
	mkdir -p $(basedir) 2> /dev/null

mk_url_title_db: connect_node3
	gxpc e 'find $(SF_DIR) -type f -name "*xml.gz" | grep -v inlink 2> /dev/null | perl $(scriptdir)/select-targetids.perl $(TARGETIDS) > $(XMLFILES)'
	gxpc e '$(PERL) $(scriptdir)/extract-url-title.perl -files $(XMLFILES) > $(URL_TITLE_TXT)'
	gxpc e mkdir -p $(workspace_mkdb) 2> /dev/null
	gxpc cd $(workspace_mkdb)
	gxpc e "perl -pe 's/ +/ /g' $(URL_TITLE_TXT) | awk '{print \$$1, \$$2}' | $(PERL) -I$(utildir)/perl $(utildir)/scripts/make-db.perl -dbname did2url.cdb -keymapfile did2url.cdb.keymap"
	gxpc e "perl -pe 's/ +/ /g' $(URL_TITLE_TXT) | awk '{print \$$1, \$$3}' | $(PERL) -I$(utildir)/perl $(utildir)/scripts/make-db.perl -dbname did2title.cdb -keymapfile did2title.cdb.keymap"
	gxpc e "perl -pe 's/ +/ /g' $(URL_TITLE_TXT) | awk '{print \$$1, \$$4}' > $(IDXID).doc_length.txt"
	gxpc quit


mk_mapfile:
	sh $(scriptdir)/make-mapfile.sh $(SFLIST) > $(mapfile)

run_mkdfdb:
	ssh $(host_of_mkdfdb) 'rm -rf $(workspace_mkdfdb)/data 2> /dev/null'
	ssh $(host_of_mkdfdb) 'mkdir -p $(workspace_mkdfdb)/data 2> /dev/null'
	for h in `cat $(host_file) | cut -f 1 -d ' '` ; do for f in `ssh $$h 'ls $(workspace_mgidx)/*.idx.df.gz 2> /dev/null'` ; do scp $$h:$$f $(host_of_mkdfdb):$(workspace_mkdfdb)/data ; done ; done
	ssh $(host_of_mkdfdb) 'sh $(scriptdir)/make-dfdb.sh -z $(workspace_mkdfdb)/data/*'

mk_taskfile_for_mgidx:
	$(eval N = $(shell expr `wc -l $(mgidx_dir)/flist | cut -f 1 -d ' '` \/ 100))
	for i in {0..$(N)} ; do echo $$i ; done | awk '{printf "task%d sh $(scriptdir)/merge-index.sh -syn $(format) $(mgidx_dir)/flist $(mapfile)\n", NR, $$0}' > $(taskfile_for_mgidx)

run_taskfile_for_mgidx: connect_node2
	gxpc e rm -fr $(workspace_mgidx) 2> /dev/null
	gxpc e mkdir -p $(workspace_mgidx) 2> /dev/null
	gxpc cd $(workspace_mgidx)
	gxpc ep $(taskfile_for_mgidx)
	gxpc e gzip *idx.df 2> /dev/null
	gxpc e ls -d $(workspace_mgidx) > /dev/null 2> /dev/null
	gxpc smask
	gxpc cd $(workspace_prefix)
	gxpc e 'tar czf $$HOSTNAME.tgz `echo $(workspace_mgidx) | rev | cut -f 1 -d \/ | rev`'
	ssh $(DIST_HOST_OF_IDX) mkdir -p $(DIST_DIR_OF_IDX)
	gxpc e 'scp $$HOSTNAME.tgz $(DIST_HOST_OF_IDX):$(DIST_DIR_OF_IDX)'
	gxpc e 'rm $$HOSTNAME.tgz'
	gxpc quit

	mv status $(mgidx_dir)/status

mk_taskfile_for_mkidx:
	mkdir -p $(mkidx_dir) 2> /dev/null
	for f in `cat $(SFLIST)` ; do echo sh $(scriptdir)/make-index.sh $(SCHEME) $(IPSJ) $$f ; done | awk '{print "task"NR, $$0}' > $(taskfile_for_mkidx)

connect_node:
	echo make connection
	for h in `cat $(host_file) | cut -f 1 -d . | perl -pe 's/\d+\$$//' | sort -u` ; do gxpc use $(access_method) $$HOSTNAME $$h ; done
	gxpc explore -t $(host_file)
	gxpc e "hostname | grep -v $$HOSTNAME\\$$"
	gxpc smask
	echo "*** USED HOSTS ***"
	gxpc e hostname

connect_node1:
	echo make connection
	for h in `cat $(host_file) | cut -f 1 -d . | perl -pe 's/\d+\$$//' | sort -u` ; do gxpc use $(access_method) $$HOSTNAME $$h ; done
	gxpc explore -t $(host_file)
	gxpc e "hostname | grep -v $$HOSTNAME\\$$"
	gxpc smask
	echo "*** USED HOSTS ***"
	gxpc e hostname

connect_node2:
	echo make connection
	for h in `cat $(host_file) | cut -f 1 -d . | perl -pe 's/\d+\$$//' | sort -u` ; do gxpc use $(access_method) $$HOSTNAME $$h ; done
	gxpc explore --children_hard_limit 1000 -t $(host_file)
	gxpc e "hostname | grep -v $$HOSTNAME\\$$"
	gxpc smask
	echo "*** USED HOSTS ***"
	gxpc e hostname

connect_node3:
	echo make connection
	for h in `cat $(host_file) | cut -f 1 -d . | perl -pe 's/\d+\$$//' | sort -u` ; do gxpc use $(access_method) $$HOSTNAME $$h ; done
	gxpc explore --children_hard_limit 1000 -t $(host_file)
	gxpc e "hostname | grep -v $$HOSTNAME\\$$"
	gxpc smask
	echo "*** USED HOSTS ***"
	gxpc e hostname

run_taskfile_for_mkidx: connect_node1
	gxpc e rm -fr $(workspace_mkidx) 2> /dev/null
	gxpc e mkdir -p $(workspace_mkidx) 2> /dev/null
	gxpc cd $(workspace_mkidx)
	gxpc ep $(taskfile_for_mkidx)
	mkdir -p $(mgidx_dir) 2> /dev/null
	gxpc e 'for f in `ls $(workspace_mkidx)/finish` ; do echo `hostname`:$(workspace_mkidx)/finish/$$f ; done' | sort -u > $(mgidx_dir)/flist
	gxpc quit
	mv status $(mkidx_dir)/status

clean: connect_node
	rm -fr $(basedir) 2> /dev/null
	gxpc e "rm -fr $(workspace_mkidx) $(workspace_mgidx) 2> /dev/null"
	gxpc quit
	ssh $(host_of_mkdfdb) "rm -fr $(workspace_mkdfdb) 2> /dev/null" 2> /dev/null
