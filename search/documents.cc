#include "common.h"
#include "documents.h"

bool Documents::and_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents) {
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

bool Documents::or_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents) {
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

bool Documents::merge_and(Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs) {
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
bool Documents::merge_phrase (Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs) {
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

bool Documents::dup_check_operation(std::vector<Document *> *docs1, std::vector<Document *> *docs2, std::vector<Document *> *dest_documents) {
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

bool Documents::merge_or(Documents *parent, CELL *cell, DocumentBuffer *_already_retrieved_docs) {
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

Documents *Documents::merge_and_or(CELL *cell, DocumentBuffer *_already_retrieved_docs) {
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
    else if (Atomp(car(cell)) && !strcmp((char *)_Atom(car(cell)), "PROX")) {
	int prox_dist = atoi((char *)_Atom(car(cdr(cell))));
	documents->set_type(DOCUMENTS_PROX);
	documents->set_prox_dist(prox_dist);

	double start = (double) gettimeofday_sec();
	documents->merge_and(documents, cdr(cdr(cell)), _already_retrieved_docs);
	double end = (double) gettimeofday_sec();
	if (VERBOSE)
	    cout << "merge_and = " << 1000 * (end - start) << " [ms]" << endl;
    }
    else if (Atomp(car(cell)) && !strcmp((char *)_Atom(car(cell)), "ORDERED_PROX")) {
	int prox_dist = atoi((char *)_Atom(car(cdr(cell))));
	documents->set_type(DOCUMENTS_ORDERED_PROX);
	documents->set_prox_dist(prox_dist);

	double start = (double) gettimeofday_sec();
	documents->merge_and(documents, cdr(cdr(cell)), _already_retrieved_docs);
	double end = (double) gettimeofday_sec();
	if (VERBOSE)
	    cout << "merge_and = " << 1000 * (end - start) << " [ms]" << endl;
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

bool Documents::read_dids(unsigned char *buffer, int &offset, int ldf, int term_type, DocumentBuffer *_already_retrieved_docs) {
    int load_dids = 0;
    bool already_retrieved_docs_exists = (_already_retrieved_docs != NULL && term_type == 1) ? true : false;
    s_documents.reserve(ldf);
    buffer += offset;
    unsigned char *head_of_scrdat = buffer + ldf * SIZEOFINT * 1;
    unsigned char *head_of_offdat = buffer + ldf * SIZEOFINT * 2;
    unsigned char *head_of_posdat = buffer + ldf * SIZEOFINT * 3;
    if (already_retrieved_docs_exists) {
	// load dids with conversion
	int *docids = new int[ldf];
	for (int i = 0; i < ldf; i++) {
	    *(docids + i) = intchar2int(buffer + i * SIZEOFINT);
	}

	// binary search
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
		    double score = 0.001 * intchar2int(buffer + ldf * 1 * SIZEOFINT + i * SIZEOFINT);

		    int pos_offset = intchar2int(head_of_offdat + i * SIZEOFINT);
		    int pos_num = intchar2int(head_of_posdat + pos_offset);


#ifdef DEBUG
		    cerr << " " << (*it);
#endif

		    doc->set_freq(score);
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
	    double score = 0.001 * intchar2int(buffer + ldf * 1 * SIZEOFINT + i * SIZEOFINT);

	    int pos_offset = intchar2int(buffer + ldf * 2 * SIZEOFINT + i * SIZEOFINT);
	    int pos_num = intchar2int(buffer + ldf * 3 * SIZEOFINT + pos_offset);
	    doc->set_freq(score);
	    doc->set_gdf(term_df);
			  
	    // cerr << "score = "<< score << " pos_off = " << pos_offset << " pos_num = " << pos_num << endl;
	    unsigned char *__buf = (unsigned char*) malloc(SIZEOFINT * (pos_num + 1));
	    memcpy (__buf, (buffer + ldf * 12 + pos_offset), SIZEOFINT * (pos_num + 1));
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

bool Documents::lookup_index(char *in_term, int term_type, std::istream *index_stream, Dbm *term_db, DocumentBuffer *_already_retrieved_docs) {
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

bool Documents::read_index(std::istream *index_stream, int term_type, DocumentBuffer *_already_retrieved_docs) {
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

bool Documents::walk_or(Document *doc_ptr) {
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


	    if ((*it)->get_type() == DOCUMENTS_ROOT || (*it)->get_type() == DOCUMENTS_AND || (*it)->get_type() == DOCUMENTS_PHRASE || (*it)->get_type() == DOCUMENTS_OR || (*it)->get_type() == DOCUMENTS_PROX || (*it)->get_type() == DOCUMENTS_ORDERED_PROX) {
		include_non_terminal_documents = true;
	    }


	    // load scores
	    gdf = (*it)->get_gdf();
	    if ((*it)->isRetrievedByBasicNode()) {
		basic_node_score_list.push_back(doc->get_score());
		basic_node_freq_list.push_back(doc->get_freq());

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
    double score = 0;
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
    int prev_pos = -1;
    std::vector<int> pos_list;
    while (1) {
	int cur_pos = pos_list_list[sorted_int[0]]->front();
	pos_list_list[sorted_int[0]]->erase(pos_list_list[sorted_int[0]]->begin());
	if (cur_pos == -1) {
	    break;
	}
	best_pos = cur_pos;

	// remove duplicate position
	if (cur_pos > prev_pos)
	    pos_list.push_back(cur_pos);
	prev_pos = cur_pos;

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
    document->set_best_region(best_pos, best_pos);

    return true;
}

bool Documents::walk_and(Document *doc_ptr) {
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
	    if ((*it)->get_type() == DOCUMENTS_TERM_STRICT || (*it)->get_type() == DOCUMENTS_AND || (*it)->get_type() == DOCUMENTS_PHRASE || (*it)->get_type() == DOCUMENTS_OR || (*it)->get_type() == DOCUMENTS_ROOT || (*it)->get_type() == DOCUMENTS_PROX || (*it)->get_type() == DOCUMENTS_ORDERED_PROX) {
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


    /*
     * 近接のチェック
     */

    // pos_record ... tid2pos
    // sorted_int ... pos2tid
    int target_num = pos_list_list.size();
    int sorted_int[target_num], pos_record[target_num], tid2idx[target_num];
    for (int i = 0; i < target_num; i++) {
	sorted_int[i] = i;
	pos_record[i] = -2; // Initailized by -2 because -1 means the end of pos_list.
	tid2idx[i] = 0;
    }

    update_sorted_int(sorted_int, tid2idx, &pos_list_list, target_num, false);

    int best_pos = -1;
    int best_begin = -1;
    int region = MAX_LENGTH_OF_DOCUMENT;
    int backup_tid2idx[target_num];
    std::vector<int> pos_list;
    bool skip_first = false;
    while (1) {
	int cur_pos = pos_list_list[sorted_int[0]]->at(tid2idx[sorted_int[0]]);
	if (cur_pos == -1)
	    break;

	// 近接向き考慮 && pos_record[0] に具体的な値 && pos_record[0] 以外に値が入るならば...
	if (get_type() == DOCUMENTS_ORDERED_PROX &&
	    pos_record[0] != -2 &&
	    sorted_int[0] != 0) {
	    skip_first = true;

	    // backup current tid2idx
	    for (int i = 0; i < target_num; i++) {
		backup_tid2idx[i] = tid2idx[i];
	    }
	    backup_tid2idx[0]++;
	}
	tid2idx[sorted_int[0]]++;
	pos_record[sorted_int[0]] = cur_pos;


	bool flag = true;
	int begin = pos_record[0];
	int end = 0;
	int total = 0;

	if (get_type() == DOCUMENTS_ORDERED_PROX) {
	    for (int i = 0; i < target_num; i++) {
		if (pos_record[i] < 0) {
		    flag = false;
		    break;
		}
		else if (i + 1 < target_num && pos_record[i + 1] < pos_record[i]) {
		    flag = false;
		    break;
		}
	    }
	    begin = pos_record[0];
	    end = pos_record[target_num - 1];
	} else {
	    for (int i = 0; i < target_num; i++) {
		if (pos_record[i] < 0) {
		    flag = false;
		    break;
		}

		if (begin > pos_record[i])
		    begin = pos_record[i];

		if (end < pos_record[i])
		    end = pos_record[i];

		total += pos_record[i];
	    }
	}

#ifdef DEBUG
	cerr << "DID " << doc_ptr->get_id();
	cerr << " POS RECORD: ";
	for (int i = 0; i < target_num; i++) {
	    cerr << i << ":" << pos_record[i] << " ";
	}
	cerr << endl;
#endif

	if (flag && ((end - begin) <= get_prox_dist())) {
	    best_begin = begin;
	    region = end - begin;

	    int ave = (end + begin) >> 1;
	    best_pos = ave;

	    pos_list.push_back(ave);
	    document->set_phrase_feature();
	}


	if (flag && get_type() == DOCUMENTS_ORDERED_PROX) {
	    for (int i = 0; i < target_num; i++) {
		tid2idx[i] = backup_tid2idx[i];
		pos_record[i] = -2;
	    }
	    skip_first = false;

	    if (pos_list_list[0]->size() >= tid2idx[0])
		break;
	}

	update_sorted_int(sorted_int, tid2idx, &pos_list_list, target_num, skip_first);
    } // end of while

    if (region == MAX_LENGTH_OF_DOCUMENT && (get_type() == DOCUMENTS_ORDERED_PROX || get_type() == DOCUMENTS_PROX)) {
	// remove
	remove_doc(doc_ptr->get_id());
	return false;
    }

    pos_list.push_back(-1);
    document->set_term_pos("AND", pos_list);
    document->set_best_pos(best_pos);
    document->set_best_region(best_begin, best_begin + region);

    return true;
}


bool Documents::update_sorted_int (int *sorted_int, int *tid2idx, std::vector<std::vector<int> *> *pos_list_list, int target_num, bool skip_first) {
    for (int i = 0; i < target_num - 1; i++) {
	if (pos_list_list->at(sorted_int[i])->at(tid2idx[sorted_int[i]]) == -1 ||
	    (pos_list_list->at(sorted_int[i + 1])->at(tid2idx[sorted_int[i + 1]]) != -1 &&
	     (pos_list_list->at(sorted_int[i])->at(tid2idx[sorted_int[i]]) > pos_list_list->at(sorted_int[i + 1])->at(tid2idx[sorted_int[i + 1]])))) {
	    int temp = sorted_int[i];
	    sorted_int[i] = sorted_int[i + 1];
	    sorted_int[i + 1] = temp;
	}
    }

    if (skip_first && sorted_int[0] == 0 && tid2idx[0] + 1 < pos_list_list->at(0)->size()) {
	tid2idx[0]++;
	return update_sorted_int (sorted_int, tid2idx, pos_list_list, target_num, skip_first);
    } else {
	return true;
    }
}



bool Documents::check_phrase (Document *doc_ptr) {
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
	    if ((*it)->get_type() == DOCUMENTS_TERM_STRICT || (*it)->get_type() == DOCUMENTS_AND || (*it)->get_type() == DOCUMENTS_PHRASE || (*it)->get_type() == DOCUMENTS_OR || (*it)->get_type() == DOCUMENTS_ROOT || (*it)->get_type() == DOCUMENTS_PROX || (*it)->get_type() == DOCUMENTS_ORDERED_PROX) {
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
	for (int i = 0; i < target_num; i++) {
	    if (pos_record[i] == -1) {
		flag = false;
		break;
	    }
	}

	if (flag) {
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

    return false;
}

bool Documents::walk_and_or(Document *doc_ptr) {

    // TERM_STRICT ならば有無をチェック
    if (get_type() == DOCUMENTS_TERM_STRICT) {
	Document *document = get_doc(doc_ptr->get_id());
	if (document == NULL)
	    return false;
	else
	    return true;
    }
    else if (get_type() == DOCUMENTS_TERM_LENIENT || get_type() == DOCUMENTS_TERM_OPTIONAL) {
	// あってもなくてもよい
	return true;
    }


    bool approximate_check_for_children = (get_type() == DOCUMENTS_OR) ? false : true;
    for (std::vector<Documents *>::iterator it = children.begin(), end = children.end(); it != end; ++it) {
	bool ret = (*it)->walk_and_or(doc_ptr);

	// 自分が OR ならば...
	if (get_type() == DOCUMENTS_OR) {
	    if (ret) {
		approximate_check_for_children = true;
	    }
	} else {
	    if (!ret) {
		approximate_check_for_children = false;
	    }
	}
    }

    if (!approximate_check_for_children) {
	return false;
    }

    if (type == DOCUMENTS_ROOT) {
	return walk_and(doc_ptr);
    }
    else if (type == DOCUMENTS_AND ||
	     type == DOCUMENTS_PHRASE ||
	     type == DOCUMENTS_PROX ||
	     type == DOCUMENTS_ORDERED_PROX) {
	return walk_and(doc_ptr);
    }
    else if (type == DOCUMENTS_OR) {
	return walk_or(doc_ptr);
    }

    return true;
}
