#include <sys/wait.h>
#include <arpa/inet.h>
#include <errno.h>
#include "common.h"
#include "hash.h"
//#include "term.h"
#include "document.h"
#include "documents.h"

std::vector<std::ifstream *> index_streams;
std::vector<Dbm *> offset_dbs;
Dbm *sid2url_cdb;
Dbm *sid2title_cdb;
MAP_IMPL<int, string> tid2sid;
MAP_IMPL<int, string> tid2url;
MAP_IMPL<int, string> tid2title;
MAP_IMPL<int, int>    tid2len;
MAP_IMPL<int, double> tid2prnk;
std::map<string, int> rmsids;

double gettimeofday_sec() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + (double)tv.tv_usec*1e-6;
}

bool sort_by_final_score(Document *left, Document *right) {
    return (left->get_final_score() > right->get_final_score());
}

// 検索に要した時間を収めたvectorを返すように
std::vector<double> *search(std::string *query,
	     std::vector<std::ifstream*> *index_streams,
	     std::vector<Dbm *> *offset_dbs,
	     MAP_IMPL<int, string> *tid2sid,
	     MAP_IMPL<int, int> *tid2len,
	     std::vector<Document *> *docs) {

    char *_query = (char*)query->c_str();
    CELL *query_cell = s_read_from_string (&_query);
    Documents *result_docs = new Documents(index_streams, offset_dbs);

    // searching
    double search_bgn = (double) gettimeofday_sec();
    result_docs->merge_and_or(car(query_cell), NULL);
    double search_end = (double) gettimeofday_sec();

    int count = 0;
    // scoring
    for (std::vector<Document *>::iterator it = result_docs->get_s_documents()->begin(); it != result_docs->get_s_documents()->end(); it++) {
	Document *doc = result_docs->get_doc((*it)->get_id());
	// 文書長の取得
	int length = 10000;
	MAP_IMPL<int, int>::iterator _length = tid2len->find((*it)->get_id());
	if (_length != tid2len->end())
	    length = (*_length).second;
	doc->set_length(length);

	// rmfilesにあればスキップ
	MAP_IMPL<int, string>::iterator _sid = tid2sid->find((*it)->get_id());
	if (_sid != tid2sid->end()) {
	    if (rmsids.find((*_sid).second) != rmsids.end())
		continue;
	}

	bool flag = result_docs->walk_and_or(*it);
	if (flag) {
	    // pagerank の取得
	    double pagerank = 0;
	    MAP_IMPL<int, double>::iterator _pagerank = tid2prnk.find((*it)->get_id());
	    if (_pagerank != tid2prnk.end())
		pagerank = (*_pagerank).second;

	    doc->set_pagerank(pagerank);
	    doc->set_strict_term_feature();
	    docs->push_back(doc);
	    count++;
	}
    }
    double score_end1 = (double) gettimeofday_sec();
    int prev = -1;
    for (std::vector<Document *>::iterator it = result_docs->get_l_documents()->begin(); it != result_docs->get_l_documents()->end(); ++it) {
	Document *doc = result_docs->get_doc((*it)->get_id());
	if (doc->get_id() < prev)
	    break;

	prev = doc->get_id();

	// 文書長の取得
	int length = 10000;
	MAP_IMPL<int, int>::iterator _length = tid2len->find((*it)->get_id());
	if (_length != tid2len->end())
	    length = (*_length).second;
	doc->set_length(length);

	// rmfilesにあればスキップ
	MAP_IMPL<int, string>::iterator _sid = tid2sid->find((*it)->get_id());
	if (_sid != tid2sid->end()) {
	    if (rmsids.find((*_sid).second) != rmsids.end())
		continue;
	}

	bool flag = result_docs->walk_and_or(*it);
	if (flag) {
	    // pagerank の取得
	    double pagerank = 0;
	    MAP_IMPL<int, double>::iterator _pagerank = tid2prnk.find((*it)->get_id());
	    if (_pagerank != tid2prnk.end())
		pagerank = (*_pagerank).second;

	    doc->set_pagerank(pagerank);
	    docs->push_back(doc);
	    count++;
	}
    }
    double score_end2 = (double) gettimeofday_sec();

    sort (docs->begin(), docs->end(), sort_by_final_score);
    double sort_end = (double) gettimeofday_sec();

    std::vector<double> *logdata = new std::vector<double>;
    logdata->push_back (1000 * (search_end - search_bgn));
    logdata->push_back (1000 * (score_end1 - search_end));
    logdata->push_back (1000 * (score_end2 - score_end1));
    logdata->push_back (1000 * (sort_end - score_end2));

    return logdata;
}

bool pushback_file_handle(string file) {
    std::ifstream *fin = new std::ifstream(file.c_str());
    if (fin) {
	index_streams.push_back(fin);
    } else {
	cerr << "Not found! (" << file << ")" << endl;
	index_streams.push_back(NULL);
    }
    return true;
}

bool init(string index_dir, string anchor_index_dir, int TSUBAKI_SLAVE_PORT, char *HOSTNAME) {
    std::string index_word_file         = index_dir + "/idx.word.dat";
    std::string index_dpnd_file         = index_dir + "/idx.dpnd.dat";
    std::string offset_word_file        = index_dir + "/offset.word.cdb.keymap";
    std::string offset_dpnd_file        = index_dir + "/offset.dpnd.cdb.keymap";
    std::string tid2sid_file            = index_dir + "/sid2tid";
    std::string sid2url_file            = index_dir + "/did2url.cdb";
    std::string sid2title_file          = index_dir + "/did2title.cdb";
    std::string tid2length_file         = index_dir + "/doc_length.txt";
    std::string rmfiles                 = index_dir + "/rmfiles";
    std::string pagerank_file           = index_dir + "/pagerank.txt";
    std::string anchor_index_word_file  = anchor_index_dir + "/idx.word.dat";
    std::string anchor_index_dpnd_file  = anchor_index_dir + "/idx.dpnd.dat";
    std::string anchor_offset_word_file = anchor_index_dir + "/offset.word.cdb.keymap";
    std::string anchor_offset_dpnd_file = anchor_index_dir + "/offset.dpnd.cdb.keymap";

    pushback_file_handle (index_word_file);
    pushback_file_handle (index_dpnd_file);
    pushback_file_handle (anchor_index_word_file);
    pushback_file_handle (anchor_index_dpnd_file);

    offset_dbs.push_back(new Dbm(offset_word_file, HOSTNAME));
    offset_dbs.push_back(new Dbm(offset_dpnd_file, HOSTNAME));
    offset_dbs.push_back(new Dbm(anchor_offset_word_file, HOSTNAME));
    offset_dbs.push_back(new Dbm(anchor_offset_dpnd_file, HOSTNAME));

    sid2url_cdb    = new Dbm(sid2url_file, HOSTNAME);
    sid2title_cdb  = new Dbm(sid2title_file, HOSTNAME);

    std::ifstream fin(tid2sid_file.c_str());
    if (fin) {
        while (!fin.eof()) {
            string sid;
            string tid;
            fin >> sid;
            fin >> tid;

            int _tid = (int)atoi(tid);
            tid2sid.insert(std::pair<int, string>(_tid, sid));

            // cdb -> map
            if (sid2url_cdb->is_open()) {
                string url = sid2url_cdb->get(sid);

                if (url.find("%") != string::npos) {
                    string::size_type pos;
                    string find_str = "%";
                    string rep_str = "@";
                    for(pos = url.find(find_str); pos != string::npos; pos = url.find(find_str, rep_str.length() + pos)) {
                        url.replace(pos, find_str.length(), rep_str);
                    }
                }

                tid2url.insert(std::pair<int, string>(_tid, url));
            }

            if (sid2title_cdb->is_open()) {
                string title = sid2title_cdb->get(sid);
                tid2title.insert(std::pair<int, string>(_tid, title));
            }
        }
        fin.close();
    }
    else {
        cerr << "Not found: " << tid2sid_file << endl;
    }

    std::ifstream fin1(tid2length_file.c_str());
    if (fin1) {
        while (!fin1.eof()) {
            string tid;
            string length;
            fin1 >> tid;
            fin1 >> length;
            int _tid = (int)atoi(tid);
            int _length = (int)atoi(length);
            tid2len.insert(std::pair<int, int>(_tid, _length));
        }
        fin1.close();
    }
    else {
        cerr << "Not found: " << tid2length_file << endl;
    }

    std::ifstream fin2(rmfiles.c_str());
    if (fin2) {
        while (!fin2.eof()) {
            string _sid;
            fin2 >> _sid;
            rmsids.insert(std::pair<string,int>(_sid, 1));
        }
        fin2.close();
    }
    // else
    //     cerr << "Not found: " << rmfiles << endl;

    std::ifstream fin3(pagerank_file.c_str());
    if (fin3) {
        while (!fin3.eof()) {
            string _tid;
            string _rnk;
            fin3 >> _tid;
            fin3 >> _rnk;
	    int tid = atoi (_tid);
	    double rank = atof (_rnk);
            tid2prnk.insert(std::pair<int,double>(tid, rank));
        }
        fin3.close();
    }
    // else
    //     cerr << "Not found: " << pagerank_file << endl;

    return true;
}

bool standalone_mode(string index_dir, string anchor_index_dir, int TSUBAKI_SLAVE_PORT, char *HOSTNAME) {

    init(index_dir, anchor_index_dir,TSUBAKI_SLAVE_PORT, HOSTNAME);

    char buf[102400];

    while (fgets(buf, sizeof(buf), stdin)) {
	std::vector<Document *> docs;
	string _query = buf;

	double search_bgn = gettimeofday_sec();
	std::vector<double> *logdata = search (&_query, &index_streams, &offset_dbs, &tid2sid, &tid2len, &docs);
	double search_end = gettimeofday_sec();

	int count = 0;
	std::ostringstream sbuf;
	cerr << "--- RESULT ---" << endl;
	for (std::vector<Document *>::iterator it = docs.begin(); it != docs.end(); it++) {
	    // テスト時はコメントアウトすること
//	    std::string sid = (*(MAP_IMPL<int, string>::iterator)tid2sid.find((*it)->get_id())).second;
//	    std::string title = (*(MAP_IMPL<int, string>::iterator)tid2title.find((*it)->get_id())).second;
//	    std::string url = (*(MAP_IMPL<int, string>::iterator)tid2url.find((*it)->get_id())).second;

//	    sbuf << ((*it)->to_string()) << " score=" << (*it)->get_final_score() << endl;
	    cerr << ((*it)->to_string()) << endl;
	    /*
	     * フレーズ検索
	    if ((*it)->get_phrase_feature() > 0) {
		sbuf << ((*it)->to_string()) << " score=" << (*it)->get_final_score() << endl;
	    }
	    */

	    if (++count >= NUM_OF_RETURN_DOCUMENTS)
	    	break;
	}
	cerr << endl;

	int hitcount = docs.size();

	sbuf << "hitcount " << hitcount << endl;
	sbuf << "HOSTNAME " << HOSTNAME << " " << TSUBAKI_SLAVE_PORT << endl;
	sbuf << "SEARCH_TIME " << logdata->at(0) << endl;
	sbuf << "SCORE_TIME " << logdata->at(1) << " " << logdata->at(2) << endl;
	sbuf << "SORT_TIME " << logdata->at(3) << endl;
	sbuf << "TOTAL_TIME " << 1000 * (search_end - search_bgn) << endl;

	cout << sbuf.str() << endl;
    }
    return true;
}

bool server_mode(string index_dir, string anchor_index_dir, int TSUBAKI_SLAVE_PORT, char *HOSTNAME) {
    int i, status;
    struct sockaddr_in sin;
    int sfd, fd;
    FILE *Infp, *Outfp;

    init (index_dir, anchor_index_dir,TSUBAKI_SLAVE_PORT, HOSTNAME);

    /* parent is going to die */
    if ((i = fork()) > 0) {
	return true;
    }
    else if (i == -1) {
	cerr << ";; unable to fork a new process" << endl;
	return false;
    }
    /* child does everything */
  
    if((sfd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
	cerr << ";; socket error" << endl;
	return false;
    }
  
    memset(&sin, 0, sizeof(sin));
    sin.sin_port = htons(TSUBAKI_SLAVE_PORT);
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(INADDR_ANY);

  
    /* bind */  
    if (bind(sfd, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
	cerr << ";; bind error" << endl;
	close(sfd);
	return false;
    }


    /* listen */  
    if (listen(sfd, SOMAXCONN) < 0) {
	cerr << ";; listen error" << endl;
	close(sfd);
	return false;
    }


    /* accept loop */
    while (1) {
	int pid;

	if ((fd = accept(sfd, NULL, NULL)) < 0) {
	    if (errno == EINTR) 
		continue;
	    cerr << ";; accept error" << endl;
	    close(sfd);
	    return false;
	}
    
	if ((pid = fork()) < 0) {
	    cerr << ";; fork error" << endl;
	    sleep(1);
	    continue;
	}

	/* child */
	if (pid == 0) {
	    char buf[102400];

	    close(sfd);
	    Infp  = fdopen(fd, "r");
	    Outfp = fdopen(fd, "w");
	    fgets(buf, sizeof(buf), Infp);

	    if (strncasecmp(buf, "QUIT", 4) == 0) {
	      fprintf(Outfp, "200 OK Quit\n");
	      fflush(Outfp);
	      exit(0);
	      shutdown(fd, 2);
	      fclose(Infp);
	      fclose(Outfp);
	      close(fd);
	      return true;
	    }

	    double arrive_time = (double) gettimeofday_sec();

	    std::ostringstream sbuf;
	    sbuf << "COMEIN " << gettimeofday_sec() << endl;

	    // string _query_str = "( (ROOT (OR ((京大 1 1000 1 0)) (AND ((京都 1 100 1 0)) ((駅 1 500 1 0)) ) ) ((アクセス 2 200 1 0)) ))";
	    string _query = buf;
	    std::vector<Document *> docs;
	    std::vector<double> *logdata = search (&_query, &index_streams, &offset_dbs, &tid2sid, &tid2len, &docs);

	    int count = 0;
	    for (std::vector<Document *>::iterator it = docs.begin(); it != docs.end(); it++) {
		std::string sid, title, url;
		MAP_IMPL<int, string>::iterator sid_it = tid2sid.find((*it)->get_id());
		if (sid_it != tid2sid.end()) {
		    sid = (*sid_it).second;
		}
		else {
		    sid = "0";
		}
		MAP_IMPL<int, string>::iterator title_it = tid2title.find((*it)->get_id());
		if (title_it != tid2title.end()) {
		    title = (*title_it).second;
		}
		else {
		    title = "none";
		}
		MAP_IMPL<int, string>::iterator url_it = tid2url.find((*it)->get_id());
		if (url_it != tid2url.end()) {
		    url = (*url_it).second;
		}
		else {
		    url = "none";
		}
		sbuf << sid << " " << title << " " << url << " " << ((*it)->to_string()) << endl;

		if (++count >= NUM_OF_RETURN_DOCUMENTS)
		    break;
	    }
	    int hitcount = docs.size();

	    sbuf << "hitcount " << hitcount << endl;
	    sbuf << "HOSTNAME " << HOSTNAME << " " << TSUBAKI_SLAVE_PORT << endl;
	    sbuf << "SEARCH_TIME " << logdata->at(0) << endl;
	    sbuf << "SCORE_TIME " << logdata->at(1) << " " << logdata->at(2) << endl;
	    sbuf << "SORT_TIME " << logdata->at(3) << endl;
	    sbuf << "LEAVE " << (gettimeofday_sec() - arrive_time) << " " << gettimeofday_sec();

	    fprintf(Outfp, "%s\n", sbuf.str().c_str());
	    fflush(Outfp);

	    // 後処理
	    shutdown(fd, 2);
	    fclose(Infp);
	    fclose(Outfp);
	    close(fd);
	    _exit(-1);
	}

	/* parent */
	close(fd);
	waitpid(-1, &status, 0); /* wait for a dead child */
    }

    return false;
}

int main(int argc, char** argv) {

    if (strcmp(argv[argc - 1], "-standalone") == 0) {
	standalone_mode (argv[1], argv[2], (int)atoi(argv[3]), argv[4]);
    } else {
	if (server_mode(argv[1], argv[2], (int)atoi(argv[3]), argv[4])) {
	    exit(0);	
	} else {
	    exit(1);
	}
    }
}
