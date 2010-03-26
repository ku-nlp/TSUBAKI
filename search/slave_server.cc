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

double gettimeofday_sec() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + (double)tv.tv_usec*1e-6;
}

bool sort_by_final_score (Document *left, Document *right) {
    return (left->get_final_score() > right->get_final_score());
}

bool search (std::string *query,
	     std::vector<std::ifstream*> *index_streams,
	     std::vector<Dbm *> *offset_dbs,
	     std::map<int, string> *tid2sid,
	     std::map<int, int> *tid2len,
	     std::vector<Document *> *docs) {

    char *_query = (char*)query->c_str();
    CELL *query_cell = s_read_from_string (&_query);
    Documents *root_docs = new Documents(index_streams, offset_dbs);
    Documents *result_docs = root_docs->merge_and_or(car(query_cell), NULL);

    int count = 0;
    for (std::vector<Document *>::iterator it = result_docs->get_s_documents()->begin(); it != result_docs->get_s_documents()->end(); it++) {
	Document *doc = result_docs->get_doc((*it)->get_id());

	int length = 10000;
	map<int, string>::iterator _sid = tid2sid->find((*it)->get_id());
	if (_sid != tid2sid->end()) {
	    map<int, int>::iterator _length = tid2len->find((*it)->get_id());
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

    for (std::vector<Document *>::iterator it = result_docs->get_l_documents()->begin(); it != result_docs->get_l_documents()->end(); it++) {
	Document *doc = result_docs->get_doc((*it)->get_id());

	int length = 10000;
	map<int, string>::iterator _sid = tid2sid->find((*it)->get_id());
	if (_sid != tid2sid->end()) {
	    map<int, int>::iterator _length = tid2len->find((*it)->get_id());
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

    sort (docs->begin(), docs->end(), sort_by_final_score);

    return true;
}

bool server_mode (string index_dir, string anchor_index_dir, int TSUBAKI_SLAVE_PORT, char *HOSTNAME) {
    int i, status;
    struct sockaddr_in sin;
    int sfd, fd;
    FILE *Infp, *Outfp;

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


    std::vector<std::ifstream *> index_streams;
    index_streams.push_back(new std::ifstream(index_word_file.c_str()));
    index_streams.push_back(new std::ifstream(index_dpnd_file.c_str()));
    index_streams.push_back(new std::ifstream(anchor_index_word_file.c_str()));
    index_streams.push_back(new std::ifstream(anchor_index_dpnd_file.c_str()));

    std::vector<Dbm *> offset_dbs;
    offset_dbs.push_back(new Dbm(offset_word_file));
    offset_dbs.push_back(new Dbm(offset_dpnd_file));
    offset_dbs.push_back(new Dbm(anchor_offset_word_file));
    offset_dbs.push_back(new Dbm(anchor_offset_dpnd_file));

    Dbm *sid2url_cdb    = new Dbm(sid2url_file.c_str());
    Dbm *sid2title_cdb  = new Dbm(sid2title_file.c_str());



    std::map<int, string> tid2sid;
    std::map<int, string> tid2url;
    std::map<int, string> tid2title;
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

    std::map<int, int> tid2len;
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
	    search (&_query, &index_streams, &offset_dbs, &tid2sid, &tid2len, &docs);
	    double search_end = (double) gettimeofday_sec();

	    int count = 0;
	    for (std::vector<Document *>::iterator it = docs.begin(); it != docs.end(); it++) {

		std::string sid = (*(map<int, string>::iterator)tid2sid.find((*it)->get_id())).second;
		std::string title = (*(map<int, string>::iterator)tid2title.find((*it)->get_id())).second;
		std::string url = (*(map<int, string>::iterator)tid2url.find((*it)->get_id())).second;
		sbuf << sid << " " << ((*it)->to_string()) << " " << title << " " << url << " " << (*it)->get_final_score() << endl;

		if (++count > NUM_OF_RETURN_DOCUMENTS)
		    break;
	    }
	    double _end = (double) gettimeofday_sec();
	    int hitcount = docs.size();

	    std::cout << HOSTNAME << " " << TSUBAKI_SLAVE_PORT << " SEARCH TIME " << 1000 * (search_end - search_bgn) << " [ms] AFTER SEARCH " << 1000 * (_end - search_end) << " [ms] HIT " << hitcount << endl;


	    sbuf << "hitcount " << hitcount << endl;
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

std::map<string, int> *load_sid2len (const char* file) {
    std::map<string, int> map;
    ifstream fin(file);
    while (!fin.eof()) {
	std::string did;
	std::string len;
	fin >> did;
	fin >> len;

	map[did] = (int)atoi(len);
    }

    return &map;
}

std::map<int, string> *load_tid2sid (const char* file) {

    std::map<int, string>* _map = new std::map<int, string>();
    ifstream fin(file);
    while (!fin.eof()) {
	string sid;
	string tid;
	fin >> sid;
	fin >> tid;

	int _tid = (int)atoi(tid);
	_map->insert(pair<int, string>(_tid, sid));
    }
    fin.close();
    return _map;
}

int main(int argc, char** argv) {
    if (server_mode(argv[1], argv[2], (int)atoi(argv[3]), argv[4])) {
	exit(0);	
    }
    else {
	exit(1);
    }
}
