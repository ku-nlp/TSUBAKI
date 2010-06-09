#ifndef SLAVE_SERVER_H
#define SLAVE_SERVER_H

#define PROXIMATE_LENGTH 100
#define TOTAL_NUMBUER_OF_DOCS 100132750
#define AVERAGE_DOC_LENGTH 907
#define WEIGHT_OF_STRICT_TERM_F 100
#define WEIGHT_OF_PROXIMATE_F 50
// #define DEBUG 0
#define TEST_MODE 0
#define VERBOSE 0
#define MAX_LENGTH_OF_DOCUMENT 1000000
#define SIZEOFINT sizeof(int)

#include "common.h"
#include "hash.h"
#include <string.h>
#include <algorithm>
# include <time.h>
# include <sys/time.h>

using std::cout;
using std::cerr;
using std::endl;

class Term {
    std::string term;
    std::vector<int> pos_list;
    double score;
    int type;
    int df;
  public:
    Term(std::string in_term, std::vector<int> &in_pos_list) {
	term = in_term;
	pos_list = in_pos_list;
    }
    bool print() {
	cout << term << " (";
	for (std::vector<int>::iterator it = pos_list.begin(), end = pos_list.end(); it != end; ++it) {
	    cout << *it << ", ";
	}
	cout << ")";
	return true;
    }
    bool set_score(double in_score) {
	score = in_score;
	return true;
    }
    std::vector<int> *get_pos() {
	return &pos_list;
    }
};

class Document {
    int id;
    int length;
    int strict_term_feature;
    int proximate_feature;
    int phrase_feature;
    int best_pos;
    int best_begin;
    int best_end;
    double freq;
    double gdf;
    double score;
    unsigned char *pos_buf;

    std::vector<int> *pos_list;
    std::vector<Term *> terms;
  public:
    Document(int in_id) {
	id = in_id;
	score = -1;
	length = 10;
	best_pos = -1;
	best_begin = -1;
	best_end = -1;

	proximate_feature = 0;
	strict_term_feature = 0;
	phrase_feature = 0;
	pos_list = NULL;
    }


    ~Document () {
	if (pos_list != NULL) {
	    delete pos_list;
	}
    }


    int get_id() {
	return id;
    }


    bool set_best_pos (int pos) {
	best_pos = pos;
	return true;
    }

    int get_best_pos () {
	return best_pos;
    }

    bool set_best_region (int begin, int end) {
	best_begin = begin;
	best_end = end;
	return true;
    }

    bool set_pos_char (unsigned char *pos_char) {
	pos_buf = pos_char;
	return true;
    }

    string to_string () {
	if (best_begin < 0) {
	    best_begin = (int)(best_pos - 0.5 * PROXIMATE_LENGTH);
	    best_end   = (int)(best_pos + 0.5 * PROXIMATE_LENGTH);
	}

	std::ostringstream _str;
	_str << id << " " << get_final_score() << " " << best_begin << " " << best_end;

	return _str.str();
    }

    bool set_length(int in_length) {
      length = in_length;
      return true;
    }

    bool set_proximate_feature() {
      proximate_feature = 1;
      return true;
    }

    bool set_strict_term_feature() {
      strict_term_feature = 1;
      return true;
    }

    bool set_phrase_feature() {
      phrase_feature = 1;
      return true;
    }

    bool get_phrase_feature() {
	return phrase_feature;
    }

    bool calc_score();
    bool set_term_pos(std::string term, std::vector<int> &in_pos_list) {
	if (pos_list == NULL) {
	    pos_list = new std::vector<int>;
	    for (std::vector<int>::iterator it = in_pos_list.begin(); it != in_pos_list.end(); it++) {
		pos_list->push_back(*it);
	    }
	} else {
	    pos_list = &in_pos_list;
	}
	return true;
    }
    std::vector<int> *get_pos() {
	if (pos_list == NULL) {
	    int pos_num = intchar2int(pos_buf);
	    pos_buf += sizeof (int);

	    pos_list = new std::vector<int>;
	    for (int i = 0; i < pos_num; i++) {
		int p = intchar2int(pos_buf);
		pos_list->push_back(p);
		pos_buf += sizeof (int);
	    }
	    pos_list->push_back(-1);
	}

	return pos_list;
    }

    bool set_freq(double in_freq) {
	freq = in_freq;
	return true;
    }
    double get_freq() {
	return freq;
    }
    bool set_gdf(double in_gdf) {
	gdf = in_gdf;
	return true;
    }
    double get_gdf() {
	return gdf;
    }
    bool set_score(double in_score) {
	score = in_score;
	return true;
    }

    double get_final_score() {
	double _score = get_score();
	return _score + (WEIGHT_OF_STRICT_TERM_F * strict_term_feature) + (WEIGHT_OF_PROXIMATE_F * proximate_feature);
    }

    double get_score() {
	if (score < 0) {
	    return calc_okapi(freq, gdf);
	} else {
	    return score;
	}
    }
    double calc_okapi(double freq, double gdf) {
	if (freq < 0) {
	    score = 0;
	} else {
	    double tf = 1 * (3 * freq) / ((0.5 + 1.5 * length / AVERAGE_DOC_LENGTH) + freq);
	    double idf = log((TOTAL_NUMBUER_OF_DOCS - gdf + 0.5) / (gdf + 0.5));
	    score = tf * idf;
	}
	return score;
    }

    bool print() {
	cout << " " << id; // << ":";
	// for (std::vector<Term *>::iterator it = terms.begin(); it != terms.end(); it++) {
	//     (*it)->print();
	// }
	return true;
    }
};

class Hashmap {
    int *_map_int;
    bool use_of_int_array;
    __gnu_cxx::hash_map<int, int> _map_map;
    // std::map<int, int> _map_map;

  public:
    Hashmap(int size) {
	use_of_int_array = false;
	if (size > 1000) {
	    use_of_int_array = true;
	    _map_int = (int *) malloc(sizeof(int) * 1000000);
	    memset(_map_int, -1, sizeof(int) * 1000000);
	} else {
	    _map_map = __gnu_cxx::hash_map<int, int>();
	}
    }

    bool add (int key, int value) {
	if (use_of_int_array) {
	    _map_int[key] = value;
	} else {
	    _map_map[key] = value;
	}
	return true;
    }

    int size () {
	if (use_of_int_array) {
	    return 1000000;
	} else {
	    return (int)_map_map.size();
	}
    }

    int get (int key) {
	if (use_of_int_array) {
	    return _map_int[key];
	} else {
	    if ((int)_map_map.size() < 1 || (int)_map_map.size() > 200000) {
		return -1;
	    }

	    if (_map_map.find(key) != _map_map.end()) {
		return _map_map[key];
	    } else {
		return -1;
	    }
	}
    }
};

class DocumentBuffer {
    std::vector<int> *buffer;

  public:
    DocumentBuffer(int size) {
	buffer = new std::vector<int>();
	// buffer->reserve(size);
    }


    ~DocumentBuffer() {
	if (buffer != NULL) {
	    delete buffer;
	}
    }


    bool add (int v) {
	buffer->push_back(v);
	return true;
    }

    bool add (int k, int v) {
	return add(k);
    }

    /*
    int get (int key) {
	if (buffer->find(key) != buffer->end) {
	    return buffer->at(key);
	}
    }
    */
    std::vector<int> *get_list () {
	std::sort(buffer->begin(), buffer->end());
	return buffer;
    }

};

class Documents {
    documents_type type;
    std::string term;
    double term_df;
    // std::istream *index_stream;
    // Dbm *term_db;
    std::vector<std::ifstream *> *index_streams;
    std::vector<Dbm *> *offset_dbs;
    bool retrievedByBasicNode;
    std::vector<Document *> s_documents;
    std::vector<Document *> l_documents;
    // std::vector<int> s_documents_index;
    // std::vector<int> l_documents_index;
    DocumentBuffer *__documents_index;
    Hashmap *s_documents_index;
    Hashmap *l_documents_index;
    // __gnu_cxx::hash_map<int, int> s_documents_index;
    // __gnu_cxx::hash_map<int, int> l_documents_index;
    // std::map<int, int> s_documents_index;
    // std::map<int, int> l_documents_index;
    // bool l_documents_inf;

    std::vector<Documents *> children;

  public:
    Documents(std::vector<std::ifstream *> *in_index_streams, std::vector<Dbm *> *in_offset_dbs) {

	index_streams = in_index_streams;
	// Set a large buffer for each stream

	/* for (std::vector<std::ifstream *>::iterator it = in_index_streams->begin(), end = in_index_streams->end(); it != end; ++it) { */
	/*     const int M = 32 * 1024 * 1024; */
	/*     char* buf = new char[M]; */
	/*     char* internal_buf = new char[M]; */
	/*     (*it)->rdbuf()->pubsetbuf(internal_buf, M); */
	/* } */

	__documents_index = NULL;
	s_documents_index = NULL;
	l_documents_index = NULL;

	offset_dbs = in_offset_dbs;
	retrievedByBasicNode = false;
    }


    ~Documents() {
	if (__documents_index != NULL) {
	    delete __documents_index;
	}
	if (s_documents_index != NULL) {
	    delete s_documents_index;
	}
	if (l_documents_index != NULL) {
	    delete l_documents_index;
	}
/*
	for (std::vector<Documents *>::iterator it = children.begin(), end = children.end(); it != end; ++it) {
	    delete (*it);
	}
*/
    }

    bool create___documents_index (int size) {
	__documents_index = new DocumentBuffer(size);
    }

    bool create_s_documents_index (int size) {
	s_documents_index = new Hashmap(size);
    }

    bool create_l_documents_index (int size) {
	l_documents_index = new Hashmap(size);
    }

    bool add___documents_index (int key, int value) {
	__documents_index->add(key);
    }

    bool add_s_documents_index (int key, int value) {
	s_documents_index->add(key, value);
    }

    bool add_l_documents_index (int key, int value) {
	l_documents_index->add(key, value);
    }

    /*
    int get___documents_index (int key) {
	return __documents_index->get(key);
    }
    */

    int get_s_documents_index (int key) {
	return s_documents_index->get(key);
    }

    int get_l_documents_index (int key) {
	return l_documents_index->get(key);
    }



    std::vector<Document *> *get_s_documents() {
	return &s_documents;
    }
    std::vector<Document *> *get_l_documents() {
	return &l_documents;
    }

    bool set_gdf(double in_gdf) {
	term_df = in_gdf;
	return true;
    }

    double get_gdf() {
	return term_df;
    }

    documents_type set_type(documents_type in_type) {
	return type = in_type;
    }

    documents_type get_type() {
	return type;
    }

    bool push_back_child_documents(Documents *child_ptr) {
	children.push_back(child_ptr);
	return true;
    }

    bool set_l_documents_inf() {
	// return l_documents_inf = true;
	l_documents.push_back(new Document(-1));
	return true;
    }

    DocumentBuffer *getDocumentIDs() {
	return __documents_index;
    }

    Document *get_doc (int doc_id) {
	if (s_documents_index->get(doc_id) > -1) {
	    return s_documents[s_documents_index->get(doc_id)];
	}
	else if (l_documents_index->get(doc_id) > -1) {
	    return l_documents[l_documents_index->get(doc_id)];
	}
	else {
	    // Not ists
	    return NULL;
	}
    }

    bool setIsRetrievedByBasicNode(int flag) {
	retrievedByBasicNode = (flag == 1) ? true : false;
	return true;
    }
    bool isRetrievedByBasicNode() {
	return retrievedByBasicNode;
    }


    bool and_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents) {
	std::vector<Document *>::iterator it1 = docs1->begin();
	std::vector<Document *>::iterator it2 = docs2->begin();

	if (it1 == docs1->end() || it2 == docs2->end()) {
	    return false;
	}
	else if (docs1->front()->get_id() == -1) {
	    *dest_documents = *docs2;
	    return true;
	}
	else if (docs2->front()->get_id() == -1) {
	    *dest_documents = *docs1;
	    return true;
	}

	while (1) {
	    if ((*it1)->get_id() > (*it2)->get_id()) {
		if (++it2 == docs2->end()) {
		    break;
		}
	    }
	    else if ((*it1)->get_id() < (*it2)->get_id()) {
		if (++it1 == docs1->end()) {
		    break;
		}
	    }
	    else {
		dest_documents->push_back(new Document((*it1)->get_id()));
		// dest_documents->push_back((*it1));
		if (++it1 == docs1->end()) {
		    break;
		}
		if (++it2 == docs2->end()) {
		    break;
		}
	    }
	}
	return true;
    }

    bool _ascending_order_sort_by_size (std::vector<Document *> *left, std::vector<Document *> *right) {
	return (left->size() < right->size());
    }

    bool or_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents) {
	std::vector<Document *>::iterator it1 = docs1->begin();
	std::vector<Document *>::iterator it2 = docs2->begin();

	if (it1 == docs1->end() && it2 == docs2->end()) {
	    return false;
	}
	else if (it1 == docs1->end()) {
	    *dest_documents = *docs2;
	    return false;
	}
	else if (it2 == docs2->end()) {
	    *dest_documents = *docs1;
	    return false;
	}
	else if (docs1->front()->get_id() == -1 || docs2->front()->get_id() == -1) {
	    dest_documents->clear();
	    dest_documents->push_back(new Document(-1));
	    return true;
	}

	while (1) {
	    if ((*it2)->get_id() < (*it1)->get_id()) {
		// dest_documents->push_back((*it2));
		dest_documents->push_back(new Document((*it2)->get_id()));

		if (++it2 == docs2->end()) {
		    for (; it1 != docs1->end(); it1++) {
			// dest_documents->push_back((*it1));
			dest_documents->push_back(new Document((*it1)->get_id()));
		    }
		    break;
		}
	    }
	    else if ((*it1)->get_id() < (*it2)->get_id()) {
		// dest_documents->push_back((*it1));
		dest_documents->push_back(new Document((*it1)->get_id()));

		if (++it1 == docs1->end()) {
		    for (; it2 != docs2->end(); it2++) {
			// dest_documents->push_back((*it2));
			dest_documents->push_back(new Document((*it2)->get_id()));
		    }
		    break;
		}
	    }
	    else { // id1 == id2
		// dest_documents->push_back((*it1));
		dest_documents->push_back(new Document((*it1)->get_id()));

		if (it1 + 1 == docs1->end()) {
		    for (it2++; it2 != docs2->end(); it2++) {
			// dest_documents->push_back((*it2));
			dest_documents->push_back(new Document((*it2)->get_id()));
		    }
		    break;
		}
		if (it2 + 1 == docs2->end()) {
		    for (it1++; it1 != docs1->end(); it1++) {
			// dest_documents->push_back((*it1));
			dest_documents->push_back(new Document((*it1)->get_id()));
		    }
		    break;
		}
		it1++;
		it2++;
	    }
	}
	return true;
    }

    bool merge_and(Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs) {

	Documents *current_documents = merge_and_or(car(cell), _already_retrieved_docs);
	double start = (double) gettimeofday_sec();
	DocumentBuffer *already_retrieved_docs  = (_already_retrieved_docs == NULL) ? current_documents->getDocumentIDs() : _already_retrieved_docs;

	parent->push_back_child_documents(current_documents);
	s_documents = *(current_documents->get_s_documents());
	l_documents = *(current_documents->get_l_documents());
	double end = (double) gettimeofday_sec();

	if (VERBOSE)
	    cout << "  hashmap = " << 1000 * (end - start) << " [ms]" << endl;

	while (!Lisp_Null(cdr(cell))) {
	    Documents backup_documents = *this;
	    Documents *next_documents = merge_and_or(car(cdr(cell)), already_retrieved_docs);
	    parent->push_back_child_documents(next_documents);

	    if (next_documents->get_type() == DOCUMENTS_TERM_OPTIONAL) {
		cell = cdr(cell);
		continue;
	    }
	    already_retrieved_docs = next_documents->getDocumentIDs();

	    // s: s and s
	    s_documents.clear();
	    and_operation(backup_documents.get_s_documents(),
			  next_documents->get_s_documents(),
			  &s_documents);

	    // l: (s and l) or (l and s) or (l and l)

	    // s and l
	    l_documents.clear();
	    and_operation(backup_documents.get_s_documents(), 
			  next_documents->get_l_documents(), 
			  &l_documents);

	    // l and s
	    std::vector<Document *> temp_documents;
	    and_operation(backup_documents.get_l_documents(), 
			  next_documents->get_s_documents(), 
			  &temp_documents);

	    std::vector<Document *> backup_l_documents = l_documents;
	    l_documents.clear(); // *** FIX ME: clear the contents ***
	    or_operation(&backup_l_documents, 
			 &temp_documents, 
			 &l_documents);

	    // l and l
	    temp_documents.clear();
	    and_operation(backup_documents.get_l_documents(), 
			  next_documents->get_l_documents(), 
			  &temp_documents);
	    backup_l_documents = l_documents; // *** FIX ME: clear the contents ***
	    l_documents.clear(); // *** FIX ME: clear the contents ***
	    or_operation(&backup_l_documents, 
			 &temp_documents, 
			 &l_documents);
	    cell = cdr(cell);
	}
	double _end = (double) gettimeofday_sec();
	if (VERBOSE)
	    cout << "  while = " << 1000 * (_end - end) << " [ms]" << endl;

	// inf nanode tyouhuku ga arieru
	std::vector<Document *> backup_l_documents = l_documents;
	l_documents.clear(); // *** FIX ME: clear the contents ***
	dup_check_operation(&backup_l_documents, &s_documents, &l_documents);

#ifdef DEBUG
	cout << "AND result:";
	print();
	cout << endl;
#endif

	// map index no sakusei
	create_s_documents_index(s_documents.size());
	create_l_documents_index(l_documents.size());
	create___documents_index(s_documents.size() + l_documents.size());

	int i = 0;
	for (std::vector<Document *>::iterator it = s_documents.begin(), end = s_documents.end(); it != end; ++it) {
	    s_documents_index->add((*it)->get_id(), i); // map index
	    __documents_index->add((*it)->get_id(), i); // map index
	    i++;
	}

	i = 0;
	for (std::vector<Document *>::iterator it = l_documents.begin(), end = l_documents.end(); it != end; ++it) {
	    l_documents_index->add((*it)->get_id(), i); // map index
	    __documents_index->add((*it)->get_id(), i); // map index
	    i++;
	}

	return true;
    }


    /*
     * フレーズ制約を満たすかどうかをチェックし、s_documents を絞る
     */
    bool merge_phrase (Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs) {
	
	Documents *current_documents = merge_and_or(car(cell), _already_retrieved_docs);
	double start = (double) gettimeofday_sec();
	DocumentBuffer *already_retrieved_docs  = (_already_retrieved_docs == NULL) ? current_documents->getDocumentIDs() : _already_retrieved_docs;

	parent->push_back_child_documents(current_documents);
	s_documents = *(current_documents->get_s_documents());
	l_documents = *(current_documents->get_l_documents());
	double end = (double) gettimeofday_sec();

	if (VERBOSE)
	    cout << "  hashmap = " << 1000 * (end - start) << " [ms]" << endl;

	/*
	 * AND search
	 */
	while (!Lisp_Null(cdr(cell))) {
	    Documents backup_documents = *this;
	    Documents *next_documents = merge_and_or(car(cdr(cell)), already_retrieved_docs);
	    parent->push_back_child_documents(next_documents);

	    already_retrieved_docs = next_documents->getDocumentIDs();

	    // s: s and s
	    s_documents.clear();
	    and_operation(backup_documents.get_s_documents(),
			  next_documents->get_s_documents(),
			  &s_documents);

	    cell = cdr(cell);
	}
	double _end = (double) gettimeofday_sec();
	if (VERBOSE)
	    cout << "  while = " << 1000 * (_end - end) << " [ms]" << endl;

	// map index no sakusei
	create_s_documents_index(s_documents.size());
	create___documents_index(s_documents.size());
	create_l_documents_index(l_documents.size());


	int i = 0;
	for (std::vector<Document *>::iterator it = s_documents.begin(), end = s_documents.end(); it != end; ++it) {
	    s_documents_index->add((*it)->get_id(), i); // map index
	    __documents_index->add((*it)->get_id(), i); // map index
	    i++;
	}


	/*
	 * check phrase
	 */
	int count = 0;

	std::vector<Document *> new_s_documents;
	for (std::vector<Document *>::iterator it = s_documents.begin(), end = s_documents.end(); it != end; ++it) {
	    bool notFound = false;
	    std::vector<std::vector<int> *> pos_list_list;
	    Document *doc = get_doc((*it)->get_id());
	    for (std::vector<Documents *>::iterator _it = children.begin(), end = children.end(); _it != end; ++_it) {
		Document *_doc = (*_it)->get_doc(doc->get_id());
		if (_doc == NULL) {
		    ++it;
		    notFound = true;
		    break;
		}

		pos_list_list.push_back(_doc->get_pos());
	    }
	    if (notFound)
		continue;

	    int target_num = pos_list_list.size();
	    int sorted_int[target_num], pos_record[target_num];
	    for (int i = 0; i < target_num; i++) {
		sorted_int[i] = i;
		pos_record[i] = -1;
	    }


	    for (int i = 0; i < target_num - 1; i++) {
		for (int j = 0; j < target_num - i - 1; j++) {
		    if (pos_list_list[sorted_int[i]]->front() == -1 ||
			(pos_list_list[sorted_int[i + 1]]->front() != -1 &&
			 (pos_list_list[sorted_int[i]]->front() > pos_list_list[sorted_int[i + 1]]->front()))) {
			int temp = sorted_int[i];
			sorted_int[i] = sorted_int[i + 1];
			sorted_int[i + 1] = temp;
		    }
		}
	    }

    
	    bool phrasal_flag = false;
	    while (1) {
		int cur_pos = pos_list_list[sorted_int[0]]->front();
		pos_list_list[sorted_int[0]]->erase(pos_list_list[sorted_int[0]]->begin());
		if (cur_pos == -1) {
		    break;
		}
		pos_record[sorted_int[0]] = cur_pos;

		bool flag = true;
		int begin = pos_record[0], end = 0;
		for (int i = 0; i < target_num; i++) {
		    if (pos_record[i] == -1) {
			flag = false;
			break;
		    }
		}

		if (flag) {
		    phrasal_flag = true;
		    for (int i = 0; i < target_num - 1; i++) {
			if (pos_record[i + 1] - pos_record[i] != 1) {
			    phrasal_flag = false;
			    break;
			}
		    }

		    if (phrasal_flag) {
			break;
		    }
		}

		for (int i = 0; i < target_num - 1; i++) {
		    if (pos_list_list[sorted_int[i]]->front() == -1 ||
			(pos_list_list[sorted_int[i + 1]]->front() != -1 &&
			 (pos_list_list[sorted_int[i]]->front() > pos_list_list[sorted_int[i + 1]]->front()))) {
			int temp = sorted_int[i];
			sorted_int[i] = sorted_int[i + 1];
			sorted_int[i + 1] = temp;
		    }
		}
	    } // end of while

	    if (phrasal_flag) {
		new_s_documents.push_back(doc);
		s_documents_index->add(doc->get_id(), count); // map index
		__documents_index->add(doc->get_id(), count); // map index
		count++;

	    }
	}

	s_documents = new_s_documents;

	return true;
    }

    bool dup_check_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents) {
	std::vector<Document *>::iterator it1 = docs1->begin();
	std::vector<Document *>::iterator it2 = docs2->begin();

	if (it1 == docs1->end() && it2 == docs2->end()) {
	    return false;
	}
	else if (it1 == docs1->end()) {
	    return false;
	}
	else if (it2 == docs2->end()) {
	    *dest_documents = *docs1;
	    return true;
	}

	while (1) {
	    if ((*it2)->get_id() < (*it1)->get_id()) {
		if (++it2 == docs2->end()) {
		    for (; it1 != docs1->end(); it1++) {
			dest_documents->push_back(new Document((*it1)->get_id()));
		    }
		    break;
		}
	    }
	    else if ((*it1)->get_id() < (*it2)->get_id()) {
		dest_documents->push_back(new Document((*it1)->get_id()));
		if (++it1 == docs1->end()) {
		    break;
		}
	    }
	    else { // id1 == id2
		if (it1 + 1 == docs1->end()) {
		    break;
		}
		if (it2 + 1 == docs2->end()) {
		    for (it1++; it1 != docs1->end(); it1++) {
			dest_documents->push_back(new Document((*it1)->get_id()));
		    }
		    break;
		}
		it1++;
		it2++;
	    }
	}
	return true;
    }

    bool merge_or(Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs) {

	double _start = (double) gettimeofday_sec();
	Documents *current_documents = merge_and_or(car(cell), _already_retrieved_docs);
	parent->push_back_child_documents(current_documents);
	s_documents = *(current_documents->get_s_documents());
	l_documents = *(current_documents->get_l_documents());

	double start = (double) gettimeofday_sec();
	if (VERBOSE)
	    cout << "  pre-processing = " << 1000 * (start - _start) << " [ms]" << endl;

	while (!Lisp_Null(cdr(cell))) {
	    Documents backup_documents = *this;
	    Documents *next_documents = merge_and_or(car(cdr(cell)), _already_retrieved_docs);

	    parent->push_back_child_documents(next_documents);

	    if (next_documents->get_type() == DOCUMENTS_TERM_OPTIONAL) {
		cell = cdr(cell);
		continue;
	    }

	    s_documents.clear(); // *** FIX ME: clear the contents ***
	    or_operation(backup_documents.get_s_documents(), 
			 next_documents->get_s_documents(), 
			 &s_documents);

	    // l_documents.clear(); // *** FIX ME: clear the contents ***
	    or_operation(backup_documents.get_l_documents(), 
			 next_documents->get_l_documents(), 
			 &l_documents);
	    cell = cdr(cell);
	}
	double end = (double) gettimeofday_sec();
	if (VERBOSE)
	    cout << "  while_or = " << 1000 * (end - start) << " [ms]" << endl;

	std::vector<Document *> backup_l_documents = l_documents;
	// l_documents.clear(); // *** FIX ME: clear the contents ***
	dup_check_operation(&backup_l_documents, &s_documents, &l_documents);

#ifdef DEBUG
	    cout << "OR result:";
	    print();
	    cout << endl;
#endif

	// map index no sakusei
	int i = 0;
	create_s_documents_index(s_documents.size());
	create_l_documents_index(l_documents.size());
	create___documents_index(s_documents.size() + l_documents.size());
	for (std::vector<Document *>::iterator it = s_documents.begin(), end = s_documents.end(); it != end; ++it) {
	    s_documents_index->add((*it)->get_id(), i); // map index
	    __documents_index->add((*it)->get_id(), i); // map index
	    i++;
	}

	i = 0;
	for (std::vector<Document *>::iterator it = l_documents.begin(), end = l_documents.end(); it != end; ++it) {
	    l_documents_index->add((*it)->get_id(), i); // map index
	    __documents_index->add((*it)->get_id(), i); // map index
	    i++;
	}

	double _end = (double) gettimeofday_sec();
	if (VERBOSE)
	    cout << "  map index sakusei = " << 1000 * (_end - end) << " [ms]" << endl;

	return true;
    }

    Documents *merge_and_or(CELL *cell, DocumentBuffer *_already_retrieved_docs) {
	Documents *documents = new Documents(index_streams, offset_dbs);

	if (Atomp(car(cell)) && !strcmp((char *)_Atom(car(cell)), "ROOT")) {
	    documents->set_type(DOCUMENTS_ROOT);
	    double start = (double) gettimeofday_sec();
	    documents->merge_and(documents, cdr(cell), _already_retrieved_docs);
	    double end = (double) gettimeofday_sec();
	    if (VERBOSE) {
		cout << "root = " << 1000 * (end - start) << " [ms]" << endl;
		cout << "-----" << (char *)_Atom(car(cell)) << "-----" << endl;
	    }
	}
	else if (Atomp(car(cell)) && !strcmp((char *)_Atom(car(cell)), "PHRASE")) {
	    documents->set_type(DOCUMENTS_PHRASE);
	    double start = (double) gettimeofday_sec();
	    documents->merge_phrase(documents, cdr(cell), _already_retrieved_docs);
	    double end = (double) gettimeofday_sec();
	    if (VERBOSE)
		cout << "merge_phr = " << 1000 * (end - start) << " [ms]" << endl;
	}
	else if (Atomp(car(cell)) && !strcmp((char *)_Atom(car(cell)), "AND")) {
	    documents->set_type(DOCUMENTS_AND);
	    double start = (double) gettimeofday_sec();
	    documents->merge_and(documents, cdr(cell), _already_retrieved_docs);
	    double end = (double) gettimeofday_sec();
	    if (VERBOSE)
		cout << "merge_and = " << 1000 * (end - start) << " [ms]" << endl;
	}
	else if (Atomp(car(cell)) && !strcmp((char *)_Atom(car(cell)), "OR")) {
	    documents->set_type(DOCUMENTS_OR);
	    double start = (double) gettimeofday_sec();
	    documents->merge_or(documents, cdr(cell), _already_retrieved_docs);
	    double end = (double) gettimeofday_sec();
	    if (VERBOSE)
		cout << "merge_or = " << 1000 * (end - start) << " [ms]" << endl;
	}
	else {
	    double start = (double) gettimeofday_sec();

	    char *current_term = (char *)_Atom(car(car(cell)));
	    int term_type = atoi((char *)_Atom(car(cdr(car(cell)))));
	    term_df = atof((char *)_Atom(car(cdr(cdr(car(cell))))));
	    int _isRetrievedByBasicNode = atoi((char *)_Atom(car(cdr(cdr(cdr(car(cell)))))));

	    int file = atoi((char *)_Atom(car(cdr(cdr(cdr(cdr(car(cell))))))));

	    term = current_term;
	    if (term_type == 1) {
		documents->set_type(DOCUMENTS_TERM_STRICT);
	    }
	    else if (term_type == 2) {
		documents->set_type(DOCUMENTS_TERM_LENIENT);
	    }
	    else if (term_type == 3) {
		documents->set_type(DOCUMENTS_TERM_OPTIONAL);
	    }

	    documents->setIsRetrievedByBasicNode(_isRetrievedByBasicNode);
	    documents->set_gdf(term_df);
	    double _start = (double) gettimeofday_sec();
	    if (VERBOSE)
		cout << "    before lookup = " << 1000 * (_start - start) << " [ms] file = " << file << endl;

	    documents->lookup_index(current_term, term_type, index_streams->at(file), offset_dbs->at(file), _already_retrieved_docs);
	    double end = (double) gettimeofday_sec();
	    if (VERBOSE)
		cout << "    lookup = " << 1000 * (end - _start) << " [ms] file = " << file << endl;
	}

	return documents;
    }

    bool calc_score() {
	for (std::vector<Document *>::iterator it = s_documents.begin(), end = s_documents.end(); it != end; ++it) {
	    (*it)->calc_score();
	}
	return true;
    }

    // lookup term from term_db


    double gettimeofday_sec() {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec + (double)tv.tv_usec*1e-6;
    }

    bool read_dids(unsigned char *buffer, int &offset, int ldf, int term_type, DocumentBuffer *_already_retrieved_docs) {
	int load_dids = 0;
	double total = 0;
	bool already_retrieved_docs_exists = (_already_retrieved_docs != NULL && term_type == 1) ? true : false;
	s_documents.reserve(ldf);
	buffer += offset;
	unsigned char *head_of_offdat = buffer + ldf * SIZEOFINT * 1;
	unsigned char *head_of_posdat = buffer + ldf * SIZEOFINT * 2;
	if (already_retrieved_docs_exists) {
	    // load dids with conversion
	    int *docids = new int[ldf];
	    for (int i = 0; i < ldf; i++) {
		*(docids + i) = intchar2int(buffer + i * SIZEOFINT);
	    }

	    // binary search
	    int i = 0, j = 0;
	    int head = 0;
	    std::vector<int> *did_list = _already_retrieved_docs->get_list();
	    for (std::vector<int>::iterator it = did_list->begin(), end = did_list->end(); it != end; ++it) {
		int tail = ldf - 1;
		while (head <= tail) {
		    if (*(docids + ((head + tail) >> 1)) - (*it) > 0) {
			tail = ((head + tail) >> 1) - 1;
		    }
		    else if (*(docids + ((head + tail) >> 1)) - (*it) < 0) {
			head = ((head + tail) >> 1) + 1;
		    }
		    else {
			int i = (head + tail) >> 1;
			Document *doc = new Document(*it);
			int pos_offset = intchar2int(head_of_offdat + i * SIZEOFINT);
			int pos_num = intchar2int(head_of_posdat + pos_offset);

#ifdef DEBUG
			cerr << " " << (*it);
#endif

			doc->set_freq(pos_num);
			doc->set_gdf(term_df);

			unsigned char *__buf = (unsigned char*) malloc(SIZEOFINT * (pos_num + 1));
			memcpy (__buf, (head_of_posdat + pos_offset), SIZEOFINT * (pos_num + 1));
			doc->set_pos_char(__buf);

			s_documents.push_back(doc);

			// map index
			__documents_index->add(*it, load_dids);
			s_documents_index->add(*it, load_dids);
			load_dids++;

			head = ((head + tail) >> 1) + 1;
			break;
		    }
		} // end of while
	    }
	} else {
	    for (int i = 0; i < ldf; i++) {
		int did = intchar2int(buffer + i * SIZEOFINT);

#ifdef DEBUG
		cerr << " " << did;
#endif
		Document *doc = new Document(did);
		int pos_offset = intchar2int(buffer + ldf * SIZEOFINT + i * SIZEOFINT);
		int pos_num = intchar2int(buffer + ldf * 2 * SIZEOFINT + pos_offset);

		doc->set_freq(pos_num);
		doc->set_gdf(term_df);
			  
//		cerr << "i=" << i << " did=" << did << " off=" << offset << " ldf=" << ldf << " posN=" << pos_num << " posOffset=" << pos_offset << endl;

		unsigned char *__buf = (unsigned char*) malloc(SIZEOFINT * (pos_num + 1));
		memcpy (__buf, (buffer + ldf * 8 + pos_offset), SIZEOFINT * (pos_num + 1));
		doc->set_pos_char(__buf);

		s_documents.push_back(doc);

		// map index
		__documents_index->add(did, load_dids);
		s_documents_index->add(did, load_dids);

		load_dids++;

#ifdef DEBUG
//		cerr << " i=" << i << " did=" << did << endl;
#endif
	    }
	}
	return true;
    }

    bool lookup_index(char *in_term, int term_type, std::istream *index_stream, Dbm *term_db, DocumentBuffer *_already_retrieved_docs) {
	std::string term_string = in_term;
	std::string address_str = term_db->get(term_string);

	if (address_str.size() != 0) {
	    long long address = atoll(address_str);
#ifdef DEBUG
		cerr << "KEY: " << term_string << ", ADDRESS: " << address << endl;
#endif
	    double start = (double) gettimeofday_sec();	
	    index_stream->seekg(address, std::ios::beg);
	    double end = (double) gettimeofday_sec();	

	    if (VERBOSE)
		cout << "      seek index = " << 1000 * (end - start) << " [ms]" <<  " " << address << " [byte]" << endl;

	    return read_index(index_stream, term_type, _already_retrieved_docs);
	}
	else {
#ifdef DEBUG
		cerr << "KEY: " << term_string << " is not found." << std::endl;
#endif

	    if (term_type == 2) {
	      set_l_documents_inf();
	    }

	    // create s_document_index, l_document_index
	    create___documents_index(0);
	    create_s_documents_index(0);
	    create_l_documents_index(0);

	    return false;
	}
    }

    bool read_index(std::istream *index_stream, int term_type, DocumentBuffer *_already_retrieved_docs) {

	int index_size = 0, offset = 0;
	unsigned char *buffer, *_buf;

	double _start = (double) gettimeofday_sec();	
	_buf = new unsigned char[SIZEOFINT];
	index_stream->read((char *) _buf, SIZEOFINT);

	index_size = intchar2int(_buf);
#ifdef DEBUG
	    cerr << "INDEX SIZE: " << index_size << std::endl;
#endif

	buffer = new unsigned char[index_size];
	index_stream->read((char *)buffer, index_size);
	double _end = (double) gettimeofday_sec();	

	int ldf;
	ldf = intchar2int(buffer + offset);
	if (VERBOSE)
	    cout << "      read index = " << 1000 * (_end - _start) << " [ms]" <<  " " << index_size << " [byte]" << " ldf = " << ldf << endl;


	offset += SIZEOFINT;
#ifdef DEBUG
	    cerr << "LDF: " << ldf << endl;
	    cerr << "DIDS:";
#endif

	double start = (double) gettimeofday_sec();
	// create s_document_index, l_document_index
	create___documents_index(ldf);
	create_s_documents_index(ldf);
	create_l_documents_index(ldf);

	double end = (double) gettimeofday_sec();
	if (VERBOSE)
	    cout << "      create index = " << 1000 * (end - start) << " [ms]" <<  " " << ldf << endl;

	read_dids(buffer, offset, ldf, term_type, _already_retrieved_docs);

	double end1 = (double) gettimeofday_sec();
	if (VERBOSE)
	    // cout << "      read dids = " << 1000 * (end1 - end) << " [ms]" <<  " " << ldf << " load dids = " << load_dids << endl;
	    cout << "      read dids = " << 1000 * (end1 - end) << " [ms]" <<  " " << ldf << endl;

#ifdef DEBUG
	    cerr << std::endl;
#endif

	// l_documents is infinite for lenient term
	if (term_type == 2) {
	    set_l_documents_inf();
	}

	return true;
    }

    bool _push_back_documents_index(int did, int value) {
	__documents_index->add(did, value);
    }

    bool _push_back_s_documents_index(int did, int value) {
	s_documents_index->add(did, value);
    }

    bool print() {
	cout << " S: ";
	for (std::vector<Document *>::iterator it = s_documents.begin(), end = s_documents.end(); it != end; ++it) {
	    (*it)->print();
	}
	cout << " L: ";
	for (std::vector<Document *>::iterator it = l_documents.begin(), end = l_documents.end(); it != end; ++it) {
	    (*it)->print();
	}
	return true;
    }

    bool walk_or(Document *doc_ptr) {

	Document *document = get_doc(doc_ptr->get_id());
	if (document == NULL) {
	    return false;
	}


	std::vector<double> basic_node_score_list;
	std::vector<double> basic_node_freq_list;
	std::vector<double> syn_node_score_list;
	std::vector<double> syn_node_freq_list;
	std::vector<std::vector<int> *> pos_list_list;
	double gdf = 0;
	bool include_non_terminal_documents = false;
	for (std::vector<Documents *>::iterator it = children.begin(), end = children.end(); it != end; ++it) {
	    Document *doc = (*it)->get_doc(doc_ptr->get_id());
	    if (doc) {
		// load positions
		pos_list_list.push_back(doc->get_pos());


		if ((*it)->get_type() == DOCUMENTS_ROOT || (*it)->get_type() == DOCUMENTS_AND || (*it)->get_type() == DOCUMENTS_PHRASE || (*it)->get_type() == DOCUMENTS_OR) {
		    include_non_terminal_documents = true;
		}


		// load scores
		if ((*it)->isRetrievedByBasicNode()) {
		    basic_node_score_list.push_back(doc->get_score());
		    basic_node_freq_list.push_back(doc->get_freq());
		    gdf = (*it)->get_gdf();

#ifdef DEBUG
			cerr << "GDF: " << gdf << endl;
#endif
		} else {
		    syn_node_score_list.push_back(doc->get_score());
		    syn_node_freq_list.push_back(doc->get_freq());
		}
	    }
	}


	// calculate scores
	double score;
	if (!include_non_terminal_documents) {
	    double basic_node_freq = (basic_node_freq_list.size() > 0) ? basic_node_freq_list.front() : syn_node_freq_list.front();
	    double freq = basic_node_freq;
#ifdef DEBUG
		cerr << "NODE FREQ " << freq;
#endif
	    for (std::vector<double>::iterator it = syn_node_freq_list.begin(), end = syn_node_freq_list.end(); it != end; ++it) {
		double diff = (*it) - basic_node_freq;
		if (diff > 0) {
		    freq += diff;
#ifdef DEBUG
			cerr << " + " << diff;
#endif
		}
	    }
#ifdef DEBUG
		cerr << endl;
#endif

	    score = doc_ptr->calc_okapi(freq, gdf);
	}
	else if (basic_node_score_list.size() == 0 && syn_node_score_list.size() == 2 && include_non_terminal_documents) {
	    if (syn_node_score_list[0] > syn_node_score_list[1]) {
		score = syn_node_score_list[0];
	    } else {
		score = syn_node_score_list[1];
	    }
	} else {
	    for (std::vector<double>::iterator it = syn_node_score_list.begin(), end = syn_node_score_list.end(); it != end; ++it) {
		score += (*it);
	    }

	    for (std::vector<double>::iterator it = basic_node_score_list.begin(), end = basic_node_score_list.end(); it != end; ++it) {
		score += (*it);
	    }
	}
	document->set_score(score);
#ifdef DEBUG
	    cerr << "OR DID: " << doc_ptr->get_id() << " TOTAL_SCORE: " << document->get_score() << endl;
#endif


	int target_num = pos_list_list.size();
	int sorted_int[target_num];
	for (int i = 0, size = pos_list_list.size(); i < size; ++i) {
	    sorted_int[i] = i;
	}

	// std::sort(&(sorted_int[0]), &(sorted_int[pos_list_list.size()]), sort_by_term_pos);
	for (int i = 0; i < target_num - 1; i++) {
	    for (int j = 0; j < target_num - i - 1; j++) {
		if (pos_list_list[sorted_int[i]]->front() == -1 ||
		    pos_list_list[sorted_int[i]]->front() > pos_list_list[sorted_int[i + 1]]->front()) {
		    int temp = sorted_int[i];
		    sorted_int[i] = sorted_int[i + 1];
		    sorted_int[i + 1] = temp;
		}
	    }
	}

	int best_pos = -1;
	std::vector<int> pos_list;
	while (1) {
	    int cur_pos = pos_list_list[sorted_int[0]]->front();
	    pos_list_list[sorted_int[0]]->erase(pos_list_list[sorted_int[0]]->begin());
	    if (cur_pos == -1) {
		break;
	    }
	    best_pos = cur_pos;

	    pos_list.push_back(cur_pos);

	    // std::sort(&(sorted_int[0]), &(sorted_int[pos_list_list.size()]), sort_by_term_pos);
	    for (int i = 0; i < target_num - 1; i++) {
		if (pos_list_list[sorted_int[i]]->front() == -1 ||
		    pos_list_list[sorted_int[i]]->front() > pos_list_list[sorted_int[i + 1]]->front()) {
		    int temp = sorted_int[i];
		    sorted_int[i] = sorted_int[i + 1];
		    sorted_int[i + 1] = temp;
		}
	    }
	} // end of while
	pos_list.push_back(-1);

#ifdef DEBUG
	    cerr << "OR DID: " << doc_ptr->get_id();
	    cerr << " POS LIST: ";
	    for (int i = 0; i < pos_list.size(); i++) {
		cerr << i << ":" << pos_list[i] << " ";
	    }
	    cerr << endl;
#endif

	document->set_term_pos("OR", pos_list);
	document->set_best_pos(best_pos);

	return true;
    }

    bool walk_and(Document *doc_ptr) {

	Document *document = get_doc(doc_ptr->get_id());
	if (document == NULL) {
	    return false;
	}

	double score = 0;
	std::vector<std::vector<int> *> pos_list_list;
	for (std::vector<Documents *>::iterator it = children.begin(), end = children.end(); it != end; ++it) {
	    Document *doc = (*it)->get_doc(doc_ptr->get_id());

	    // for TERM_OPTIONAL documents
	    if (doc) {
		if ((*it)->get_type() == DOCUMENTS_TERM_STRICT || (*it)->get_type() == DOCUMENTS_AND || (*it)->get_type() == DOCUMENTS_PHRASE || (*it)->get_type() == DOCUMENTS_OR || (*it)->get_type() == DOCUMENTS_ROOT) {
		    pos_list_list.push_back(doc->get_pos());
		    document->set_best_pos(doc->get_best_pos());
		}
		score += doc->get_score();

#ifdef DEBUG
		if (get_type() == DOCUMENTS_ROOT) {
		    cerr << "ROOT DID: " << doc_ptr->get_id() << " SCORE: " << doc->get_score() << endl;
		} else {
		    cerr << "AND DID: " << doc_ptr->get_id() << " SCORE: " << doc->get_score() << endl;
		}
#endif
	    }
	}

	document->set_score(score);
#ifdef DEBUG
	if (get_type() == DOCUMENTS_ROOT) {
	    cerr << "ROOT DID: " << doc_ptr->get_id() << " TOTAL_SCORE: " << document->get_score() << endl;
	} else {
	    cerr << "AND DID: " << doc_ptr->get_id() << " TOTAL_SCORE: " << document->get_score() << endl;
	}
#endif

	if (get_type() == DOCUMENTS_ROOT) {
#ifdef DEBUG
	    cerr << "ROOT DID: " << doc_ptr->get_id() << " POS LIST";
	    for (std::vector<int>::iterator it = pos_list_list[0]->begin(), end = pos_list_list[0]->end(); it != end; ++it) {
		cerr << " " << (*it);
	    }
	    cerr << endl;
#endif

	    if (*(pos_list_list[0]->begin()) != -1) {
		document->set_proximate_feature();
	    }

	    document->set_term_pos("ROOT", *(pos_list_list[0]));

	    return true;
	}

	int target_num = pos_list_list.size();
	int sorted_int[target_num], pos_record[target_num];
	for (int i = 0; i < target_num; i++) {
	    sorted_int[i] = i;
	    pos_record[i] = -1;
	}

	// std::sort(&(sorted_int[0]), &(sorted_int[pos_list_list.size()]), sort_by_term_pos);
	for (int i = 0; i < target_num - 1; i++) {
	    for (int j = 0; j < target_num - i - 1; j++) {
		if (pos_list_list[sorted_int[i]]->front() == -1 ||
		    (pos_list_list[sorted_int[i + 1]]->front() != -1 &&
		     (pos_list_list[sorted_int[i]]->front() > pos_list_list[sorted_int[i + 1]]->front()))) {
		    int temp = sorted_int[i];
		    sorted_int[i] = sorted_int[i + 1];
		    sorted_int[i + 1] = temp;
		}
	    }
	}

	int best_pos = -1;
	int best_begin = -1;
	int region = MAX_LENGTH_OF_DOCUMENT;
	std::vector<int> pos_list;
	while (1) {
	    int cur_pos = pos_list_list[sorted_int[0]]->front();

	    pos_list_list[sorted_int[0]]->erase(pos_list_list[sorted_int[0]]->begin());
	    if (cur_pos == -1) {
		break;
	    }
	    pos_record[sorted_int[0]] = cur_pos;


	    bool flag = true;
	    int begin = pos_record[0];
	    int end = 0;
	    int total = 0;
	    for (int i = 0; i < target_num; i++) {
		if (pos_record[i] == -1) {
		    flag = false;
		    break;
		}

		if (begin > pos_record[i]) {
		    begin = pos_record[i];
		}

		if (end < pos_record[i]) {
		    end = pos_record[i];
		}

		total += pos_record[i];
	    }

#ifdef DEBUG
            cerr << "DID " << doc_ptr->get_id();
	    cerr << " POS RECORD: ";
            for (int i = 0; i < target_num; i++) {
		cerr << i << ":" << pos_record[i] << " ";
            }
	    cerr << endl;
#endif

//          cerr << "flag=" << flag << " begin=" <<  begin << " end=" << end << " region=" << region << endl;
	    if (flag && ((end - begin) <= region)) {
//	    if (flag && ((end - begin) == target_num)) {
		best_begin = begin;
		region = end - begin;

		int ave = (end + begin) >> 1;
		best_pos = ave;

	        document->set_phrase_feature();

		if ((end - begin) < PROXIMATE_LENGTH) {
		    pos_list.push_back(ave);
		}
	    }

	    // std::sort(&(sorted_int[0]), &(sorted_int[pos_list_list.size()]), sort_by_term_pos);
	    for (int i = 0; i < target_num - 1; i++) {
		if (pos_list_list[sorted_int[i]]->front() == -1 ||
		    (pos_list_list[sorted_int[i + 1]]->front() != -1 &&
		     (pos_list_list[sorted_int[i]]->front() > pos_list_list[sorted_int[i + 1]]->front()))) {
		    int temp = sorted_int[i];
		    sorted_int[i] = sorted_int[i + 1];
		    sorted_int[i + 1] = temp;
		}
	    }
	} // end of while

	pos_list.push_back(-1);
	document->set_term_pos("AND", pos_list);
	document->set_best_pos(best_pos);
	document->set_best_region(best_begin, best_begin + region);

	return true;
    }



    bool check_phrase (Document *doc_ptr) {

	Document *document = get_doc(doc_ptr->get_id());
	if (document == NULL) {
	    return false;
	}

	double score = 0;
	std::vector<std::vector<int> *> pos_list_list;
	for (std::vector<Documents *>::iterator it = children.begin(), end = children.end(); it != end; ++it) {
	    Document *doc = (*it)->get_doc(doc_ptr->get_id());

	    // for TERM_OPTIONAL documents
	    if (doc) {
		if ((*it)->get_type() == DOCUMENTS_TERM_STRICT || (*it)->get_type() == DOCUMENTS_AND || (*it)->get_type() == DOCUMENTS_PHRASE || (*it)->get_type() == DOCUMENTS_OR || (*it)->get_type() == DOCUMENTS_ROOT) {
		    pos_list_list.push_back(doc->get_pos());
		    document->set_best_pos(doc->get_best_pos());
		}
		score += doc->get_score();
	    }
	}
	document->set_score(score);


	int target_num = pos_list_list.size();
	int sorted_int[target_num], pos_record[target_num];
	for (int i = 0; i < target_num; i++) {
	    sorted_int[i] = i;
	    pos_record[i] = -1;
	}

	for (int i = 0; i < target_num - 1; i++) {
	    for (int j = 0; j < target_num - i - 1; j++) {
		if (pos_list_list[sorted_int[i]]->front() == -1 ||
		    (pos_list_list[sorted_int[i + 1]]->front() != -1 &&
		     (pos_list_list[sorted_int[i]]->front() > pos_list_list[sorted_int[i + 1]]->front()))) {
		    int temp = sorted_int[i];
		    sorted_int[i] = sorted_int[i + 1];
		    sorted_int[i + 1] = temp;
		}
	    }
	}

	std::vector<int> pos_list;
	while (1) {
	    int cur_pos = pos_list_list[sorted_int[0]]->front();

	    pos_list_list[sorted_int[0]]->erase(pos_list_list[sorted_int[0]]->begin());
	    if (cur_pos == -1) {
		break;
	    }
	    pos_record[sorted_int[0]] = cur_pos;


	    bool flag = true;
	    int begin = pos_record[0], end = 0;
	    for (int i = 0; i < target_num; i++) {
		if (pos_record[i] == -1) {
		    flag = false;
		    break;
		}
	    }



	    if (doc_ptr->get_id() == 962783) {
		cerr << "POS RECORD: ";
		for (int i = 0; i < target_num; i++) {
		    cerr << pos_record[i] << " ";
		}
		cerr << endl;
	    }

	    if (flag) {

		if (doc_ptr->get_id() == 962783) {
		    cerr << "flag = " << flag << endl;
		}


		bool phrasal_flag = true;
		for (int i = 0; i < target_num - 1; i++) {
		    if (pos_record[i + 1] - pos_record[i] != 1) {
			phrasal_flag = false;
			break;
		    }
		}

		if (phrasal_flag) {
		    if (doc_ptr->get_id() == 962783) {
			cerr << "match." << endl;
		    }
		    return true;
		}
	    }

	    for (int i = 0; i < target_num - 1; i++) {
		if (pos_list_list[sorted_int[i]]->front() == -1 ||
		    (pos_list_list[sorted_int[i + 1]]->front() != -1 &&
		     (pos_list_list[sorted_int[i]]->front() > pos_list_list[sorted_int[i + 1]]->front()))) {
		    int temp = sorted_int[i];
		    sorted_int[i] = sorted_int[i + 1];
		    sorted_int[i + 1] = temp;
		}
	    }
	} // end of while
	pos_list.push_back(-1);

	if (doc_ptr->get_id() == 962783) {
	    cerr << "missmatch." << endl;
	}
	return false;
    }


    bool walk_and_or(Document *doc_ptr) {

	for (std::vector<Documents *>::iterator it = children.begin(), end = children.end(); it != end; ++it) {
	    if ((*it)->get_type() == DOCUMENTS_AND || (*it)->get_type() == DOCUMENTS_PHRASE  || (*it)->get_type() == DOCUMENTS_OR) {
		bool flag = (*it)->walk_and_or(doc_ptr);
		if (get_type() == DOCUMENTS_AND || get_type() == DOCUMENTS_ROOT) {
		    if (!flag)
			return false;
		}
	    }
	    else if ((*it)->get_type() == DOCUMENTS_ROOT) {
		return (*it)->walk_and_or(doc_ptr);
	    }
	}

	if (type == DOCUMENTS_ROOT) {
//	    walk_and(doc_ptr);
	}
	else if (type == DOCUMENTS_AND) {
	    walk_and(doc_ptr);
	}
	else if (type == DOCUMENTS_OR) {
	    walk_or(doc_ptr);
	}

	return true;
    }
};

class sort_by_term_pos {
    std::vector<std::vector<int> *> *pos_list_list_ptr;
  public:
    sort_by_term_pos(std::vector<std::vector<int> *> *in_pos_list_list_ptr) {
	pos_list_list_ptr = in_pos_list_list_ptr;
    }
    bool operator() (int left, int right) {
	if (pos_list_list_ptr->at(left)->front() == -1) {
	    return true;
	}
	else if (pos_list_list_ptr->at(right)->front() == -1) {
	    return false;
	}
	else if (pos_list_list_ptr->at(left)->front() > pos_list_list_ptr->at(right)->front()) {
	    return true;
	}
	else {
	    return false;
	}
    }
};

#endif
