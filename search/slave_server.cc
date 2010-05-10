# include <iostream>
# include <stdio.h>
# include <unistd.h>
# include <sys/socket.h>
# include <sys/wait.h>
# include <arpa/inet.h>
# include <signal.h>
# include <errno.h>
# include "slave_server.h"
# include <fstream>
# include <iostream>
# include <algorithm>
# include <time.h>
# include <sys/time.h>

# define NUM_OF_RETURN_DOCUMENTS 30

using namespace std;

std::vector<std::ifstream *> index_streams;
std::vector<Dbm *> offset_dbs;
Dbm *sid2url_cdb;
Dbm *sid2title_cdb;
__gnu_cxx::hash_map<int, string> tid2sid;
__gnu_cxx::hash_map<int, string> tid2url;
__gnu_cxx::hash_map<int, string> tid2title;
__gnu_cxx::hash_map<int, int> tid2len;

double gettimeofday_sec() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + (double)tv.tv_usec*1e-6;
}

bool sort_by_final_score (Document *left, Document *right) {
    return (left->get_final_score() > right->get_final_score());
}

// 検索に要した時間を収めたvectorを返すように
std::vector<double> *search (std::string *query,
	     std::vector<std::ifstream*> *index_streams,
	     std::vector<Dbm *> *offset_dbs,
	     __gnu_cxx::hash_map<int, string> *tid2sid,
	     __gnu_cxx::hash_map<int, int> *tid2len,
	     std::vector<Document *> *docs) {

    char *_query = (char*)query->c_str();
    CELL *query_cell = s_read_from_string (&_query);
    Documents *root_docs = new Documents(index_streams, offset_dbs);

    // searching
    double search_bgn = (double) gettimeofday_sec();
    Documents *result_docs = root_docs->merge_and_or(car(query_cell), NULL);
    double search_end = (double) gettimeofday_sec();

    int count = 0;
    // scoring
    for (std::vector<Document *>::iterator it = result_docs->get_s_documents()->begin(); it != result_docs->get_s_documents()->end(); it++) {
	Document *doc = result_docs->get_doc((*it)->get_id());

	int length = 10000;
	__gnu_cxx::hash_map<int, string>::iterator _sid = tid2sid->find((*it)->get_id());
	if (_sid != tid2sid->end()) {
	    __gnu_cxx::hash_map<int, int>::iterator _length = tid2len->find((*it)->get_id());
	    if (_length != tid2len->end()) {
		std::string _val = (*_sid).second;
		length = (int)atoi(_val);
	    }
	}

	doc->set_length(length);

	result_docs->walk_and_or(*it);
	doc->set_strict_term_feature();
	docs->push_back(doc);
	count++;
    }
    double score_end1 = (double) gettimeofday_sec();

    for (std::vector<Document *>::iterator it = result_docs->get_l_documents()->begin(); it != result_docs->get_l_documents()->end(); it++) {
	Document *doc = result_docs->get_doc((*it)->get_id());

	int length = 10000;
	__gnu_cxx::hash_map<int, string>::iterator _sid = tid2sid->find((*it)->get_id());
	if (_sid != tid2sid->end()) {
	    __gnu_cxx::hash_map<int, int>::iterator _length = tid2len->find((*it)->get_id());
	    if (_length != tid2len->end()) {
		std::string _val = (*_sid).second;
		length = (int)atoi(_val);
	    }
	}

	doc->set_length(length);

	result_docs->walk_and_or(*it);
	docs->push_back(doc);
	count++;
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

bool init (string index_dir, string anchor_index_dir, int TSUBAKI_SLAVE_PORT, char *HOSTNAME) {
    std::string index_word_file         = index_dir + "/index000.word.conv.data";
    std::string index_dpnd_file         = index_dir + "/index000.dpnd.conv.data";
    std::string offset_word_file        = index_dir + "/offset000.word.conv.txt.cdb.0";
    std::string offset_dpnd_file        = index_dir + "/offset000.dpnd.conv.txt.cdb.0";
    std::string tid2sid_file            = index_dir + "/sid2tid";
    std::string sid2url_file            = index_dir + "/did2url.cdb";
    std::string sid2title_file          = index_dir + "/did2title.cdb";
    std::string tid2length_file         = index_dir + "/000.doc_length.txt";
    std::string anchor_index_word_file  = anchor_index_dir + "/index000.word.conv.data";
    std::string anchor_index_dpnd_file  = anchor_index_dir + "/index000.dpnd.conv.data";
    std::string anchor_offset_word_file = anchor_index_dir + "/offset000.word.conv.txt.cdb.0";
    std::string anchor_offset_dpnd_file = anchor_index_dir + "/offset000.dpnd.conv.txt.cdb.0";

    index_streams.push_back(new std::ifstream(index_word_file.c_str()));
    index_streams.push_back(new std::ifstream(index_dpnd_file.c_str()));
    index_streams.push_back(new std::ifstream(anchor_index_word_file.c_str()));
    index_streams.push_back(new std::ifstream(anchor_index_dpnd_file.c_str()));

    offset_dbs.push_back(new Dbm(offset_word_file));
    offset_dbs.push_back(new Dbm(offset_dpnd_file));
    offset_dbs.push_back(new Dbm(anchor_offset_word_file));
    offset_dbs.push_back(new Dbm(anchor_offset_dpnd_file));

    sid2url_cdb    = new Dbm(sid2url_file.c_str());
    sid2title_cdb  = new Dbm(sid2title_file.c_str());

    ifstream fin(tid2sid_file.c_str());
    while (!fin.eof()) {
	string sid;
	string tid;
	fin >> sid;
	fin >> tid;

	int _tid = (int)atoi(tid);
	tid2sid.insert(pair<int, string>(_tid, sid));

	// cdb -> map
	string url = sid2url_cdb->get(sid);
	string title = sid2title_cdb->get(sid);

	tid2url.insert(pair<int, string>(_tid, url));
	tid2title.insert(pair<int, string>(_tid, title));
    }
    fin.close();

    ifstream fin1(tid2length_file.c_str());
    while (!fin1.eof()) {
	string tid;
	string length;
	fin1 >> tid;
	fin1 >> length;
	int _tid = (int)atoi(tid);
	int _length = (int)atoi(length);
	tid2len.insert(pair<int, int>(_tid, _length));
    }
    fin1.close();
}

bool standalone_mode (string index_dir, string anchor_index_dir, int TSUBAKI_SLAVE_PORT, char *HOSTNAME) {
    int i, status;
    struct sockaddr_in sin;
    int sfd, fd;
    FILE *Infp, *Outfp;

    init (index_dir, anchor_index_dir,TSUBAKI_SLAVE_PORT, HOSTNAME);

    std::vector<Document *> docs;
    double search_bgn = (double) gettimeofday_sec();
    string _query = "( (ROOT (AND ((上野 1 898224 1 0)) ((動物 1 3266111 1 0)) (OR ((動物 1 3266111 1 0)) ((s30329:動物 1 3266111 0 0)) ((s10464:動物 1 3266111 0 0)) ) ((園 1 3301610 1 0)) (OR ((調べる 1 3576321 1 0)) ((s1311:捜す 1 3576321 0 0)) ((s21826:しらべる 1 3576321 0 0)) ((s11793:調べる 1 3576321 0 0)) ((s4363:調べる 1 3576321 0 0)) ((s137:調査 1 3576321 0 0)) ((s778:検査 1 3576321 0 0)) ) (OR ((煎る 1 11561686 1 0)) ((要る 1 11561686 0 0)) ((射る 1 11561686 0 0)) ((居る 1 11561686 0 0)) ((鋳る 1 11561686 0 0)) ((s275:不要だ<否定> 1 11561686 0 0)) ((s576:不用だ<否定> 1 11561686 0 0)) ((s1140:要る 1 11561686 0 0)) ((s34434:射る 1 11561686 0 0)) ((s17902:射る 1 11561686 0 0)) ((s229:居る 1 11561686 0 0)) ((s29303:鋳る 1 11561686 0 0)) ) ((上野->動物 2 34620 1 1)) ((動物->園 2 582443 1 1)) ) ((動物->調べる 3 742 1 1)) ((鋳る->動物 3 4917 1 1)) ((居る->動物 3 5183 1 1)) ((園->要る 3 10355 1 1)) ((園->鋳る 3 10145 1 1)) ((要る->動物 3 5620 1 1)) ((園->射る 3 10360 1 1)) ((園->居る 3 11823 1 1)) ((園->煎る 3 10384 1 1)) ((煎る->動物 3 5633 1 1)) ((射る->動物 3 6061 1 1)) ((上野 3 898224 1 2)) ((動物 3 3266111 1 2)) ((動物 3 3266111 1 2)) ((s30329:動物 3 3266111 1 2)) ((s10464:動物 3 3266111 1 2)) ((園 3 3301610 1 2)) ((調べる 3 3576321 1 2)) ((s1311:捜す 3 3576321 1 2)) ((s21826:しらべる 3 3576321 1 2)) ((s11793:調べる 3 3576321 1 2)) ((s4363:調べる 3 3576321 1 2)) ((s137:調査 3 3576321 1 2)) ((s778:検査 3 3576321 1 2)) ((煎る 3 11561686 1 2)) ((要る 3 11561686 1 2)) ((射る 3 11561686 1 2)) ((居る 3 11561686 1 2)) ((鋳る 3 11561686 1 2)) ((s275:不要だ<否定> 3 11561686 1 2)) ((s576:不用だ<否定> 3 11561686 1 2)) ((s1140:要る 3 11561686 1 2)) ((s34434:射る 3 11561686 1 2)) ((s17902:射る 3 11561686 1 2)) ((s229:居る 3 11561686 1 2)) ((s29303:鋳る 3 11561686 1 2)) ((上野->動物 3 34620 1 3)) ((動物->園 3 582443 1 3)) ) )";
    std::vector<double> *logdata = search (&_query, &index_streams, &offset_dbs, &tid2sid, &tid2len, &docs);
    double search_end = (double) gettimeofday_sec();

    int count = 0;
    std::ostringstream sbuf;
    for (std::vector<Document *>::iterator it = docs.begin(); it != docs.end(); it++) {
	std::string sid = (*(__gnu_cxx::hash_map<int, string>::iterator)tid2sid.find((*it)->get_id())).second;
	std::string title = (*(__gnu_cxx::hash_map<int, string>::iterator)tid2title.find((*it)->get_id())).second;
	std::string url = (*(__gnu_cxx::hash_map<int, string>::iterator)tid2url.find((*it)->get_id())).second;
	sbuf << sid << " " << ((*it)->to_string()) << " " << title << " " << url << " " << (*it)->get_final_score() << endl;
	sbuf << ((*it)->to_string()) << " score=" << (*it)->get_final_score() << endl;

	if (++count > NUM_OF_RETURN_DOCUMENTS)
	    break;
    }
    double _end = (double) gettimeofday_sec();
    int hitcount = docs.size();

    sbuf << "hitcount " << hitcount << endl;
    sbuf << "HOSTNAME " << HOSTNAME << " " << TSUBAKI_SLAVE_PORT << endl;
    sbuf << "SEARCH_TIME " << logdata->at(0) << endl;
    sbuf << "SCORE_TIME " << logdata->at(1) << " " << logdata->at(2) << endl;
    sbuf << "SORT_TIME " << logdata->at(3) << endl;
    sbuf << "TOTAL_TIME " << 1000 * (search_end - search_bgn) << endl;

    cout << sbuf.str() << endl;
    return true;
}

bool server_mode (string index_dir, string anchor_index_dir, int TSUBAKI_SLAVE_PORT, char *HOSTNAME) {
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
	    double search_bgn = (double) gettimeofday_sec();
	    std::vector<double> *logdata = search (&_query, &index_streams, &offset_dbs, &tid2sid, &tid2len, &docs);
	    // search (&_query, &index_streams, &offset_dbs, &tid2sid, &tid2len, &docs);
	    double search_end = (double) gettimeofday_sec();

	    int count = 0;
	    for (std::vector<Document *>::iterator it = docs.begin(); it != docs.end(); it++) {

		std::string sid = (*(__gnu_cxx::hash_map<int, string>::iterator)tid2sid.find((*it)->get_id())).second;
		std::string title = (*(__gnu_cxx::hash_map<int, string>::iterator)tid2title.find((*it)->get_id())).second;
		std::string url = (*(__gnu_cxx::hash_map<int, string>::iterator)tid2url.find((*it)->get_id())).second;
		sbuf << sid << " " << ((*it)->to_string()) << " " << title << " " << url << " " << (*it)->get_final_score() << endl;

		if (++count > NUM_OF_RETURN_DOCUMENTS)
		    break;
	    }
	    double scornd = (double) gettimeofday_sec();
	    int hitcount = docs.size();


	    sbuf << "hitcount " << hitcount << endl;
	    sbuf << "HOSTNAME " << HOSTNAME << " " << TSUBAKI_SLAVE_PORT << endl;
	    sbuf << "SEARCH_TIME " << logdata->at(0) << endl;
	    sbuf << "SCORE_TIME " << logdata->at(1) << " " << logdata->at(2) << endl;
	    sbuf << "SORT_TIME " << logdata->at(3) << endl;
	    sbuf << "LEAVE " << (gettimeofday_sec() - arrive_time) << " " << gettimeofday_sec();

	    fprintf(Outfp, sbuf.str().c_str());
	    fprintf(Outfp, "\n");
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
	waitpid(-1, &status, WNOHANG); /* wait for a dead child */
    }

    return false;
}

int main (int argc, char** argv) {

    if (strcmp(argv[5], "-standalone") == 0) {
	standalone_mode (argv[1], argv[2], (int)atoi(argv[3]), argv[4]);
    } else {
	if (server_mode(argv[1], argv[2], (int)atoi(argv[3]), argv[4])) {
	    exit(0);	
	} else {
	    exit(1);
	}
    }
}
