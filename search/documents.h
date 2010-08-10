#ifndef DOCUMENTS_H
#define DOCUMENTS_H

#include "hash.h"
#include "document.h"
#include <time.h>
#include <sys/time.h>

class Hashmap {
    int *_map_int;
    bool use_of_int_array;
    MAP_IMPL<int, int> _map_map;

  public:
    Hashmap(int size) {
	use_of_int_array = false;
	if (size > 1000) {
	    use_of_int_array = true;
	    _map_int = (int *) malloc(sizeof(int) * 1000000);
	    memset(_map_int, -1, sizeof(int) * 1000000);
	} else {
	    _map_map = MAP_IMPL<int, int>();
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

    int size () {
	return buffer->size();
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
    // MAP_IMPL<int, int> s_documents_index;
    // MAP_IMPL<int, int> l_documents_index;
    // bool l_documents_inf;
    int prox_dist;
    string label;
    std::vector<Term *> terms;
    std::vector<Documents *> children;

  public:
    Documents(std::vector<std::ifstream *> *in_index_streams, std::vector<Dbm *> *in_offset_dbs) {

	index_streams = in_index_streams;

	__documents_index = NULL;
	s_documents_index = NULL;
	l_documents_index = NULL;

	offset_dbs = in_offset_dbs;
	retrievedByBasicNode = false;

	prox_dist = PROXIMATE_LENGTH;
	label = "none";
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


    bool set_label (string _label, int type) {
	if (type > 1) {
	    _label += "_LK";
	}

	label = _label;
	return true;
    }

    string get_label () {
	return label;
    }

    void set_prox_dist (int dist) {
	prox_dist = dist;
    }

    void create___documents_index (int size) {
	__documents_index = new DocumentBuffer(size);
    }

    void create_s_documents_index (int size) {
	s_documents_index = new Hashmap(size);
    }

    void create_l_documents_index (int size) {
	l_documents_index = new Hashmap(size);
    }

    void add___documents_index (int key, int value) {
	__documents_index->add(key);
    }

    void add_s_documents_index (int key, int value) {
	s_documents_index->add(key, value);
    }

    void add_l_documents_index (int key, int value) {
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

    bool update_sorted_int (int *sorted_int, int *tid2idx, std::vector<std::vector<int> *> *pos_list_list, int target_num, bool skip_first);

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

    bool remove_doc (int doc_id) {
	if (s_documents_index->get(doc_id) > -1) {
	    s_documents_index->add(doc_id, -1);
	}
	else if (l_documents_index->get(doc_id) > -1) {
	    l_documents_index->add(doc_id, -1);
	}
	else {
	    // Not ists
	    return false;
	}
	return true;
    }

    bool setIsRetrievedByBasicNode(int flag) {
	retrievedByBasicNode = (flag == 1) ? true : false;
	return true;
    }
    bool isRetrievedByBasicNode() {
	return retrievedByBasicNode;
    }

    bool and_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents);

    bool _ascending_order_sort_by_size (std::vector<Document *> *left, std::vector<Document *> *right) {
	return (left->size() < right->size());
    }

    bool or_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents);
    bool merge_and(Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs);
    bool merge_phrase (Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs);
    bool dup_check_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents);
    bool merge_or(Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs);
    Documents *merge_and_or(CELL *cell, DocumentBuffer *_already_retrieved_docs);

    int get_prox_dist() {
	return prox_dist;
    }

    bool calc_score() {
	for (std::vector<Document *>::iterator it = s_documents.begin(), end = s_documents.end(); it != end; ++it) {
	    (*it)->calc_score();
	}
	return true;
    }

    double gettimeofday_sec() {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec + (double)tv.tv_usec*1e-6;
    }

    bool read_dids(unsigned char *buffer, int &offset, int ldf, int term_type, DocumentBuffer *_already_retrieved_docs);
    bool lookup_index(char *in_term, int term_type, std::istream *index_stream, Dbm *term_db, DocumentBuffer *_already_retrieved_docs);
    bool read_index(std::istream *index_stream, int term_type, DocumentBuffer *_already_retrieved_docs);

    void _push_back_documents_index(int did, int value) {
	__documents_index->add(did, value);
    }

    void _push_back_s_documents_index(int did, int value) {
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

    bool walk_or(Document *doc_ptr);
    bool walk_and(Document *doc_ptr);
    bool check_phrase (Document *doc_ptr);
    bool walk_and_or(Document *doc_ptr);
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
