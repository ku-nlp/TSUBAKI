#include "common.h"
#include "document.h"

std::string Document::to_string () {
    std::ostringstream _str;
    _str << id << " " << get_final_score() << " " << get_length() << " " << best_begin << " " << best_end << " [";
    for (std::vector<Term*>::iterator it = terms.begin(); it != terms.end(); it++) {
	_str << (*it)->to_string() << ",";
    }
    _str << "]";

    return _str.str();
}

bool Document::set_term_pos(std::string term, std::vector<int> *in_pos_list) {
    if (pos_list == in_pos_list) { // do nothing if input is the pointer of this->pos_list
	return true;
    }
    else {
	if (pos_list) { // delete pos_list if available
	    delete pos_list;
	}

	pos_list = new std::vector<int>;
	for (std::vector<int>::iterator it = in_pos_list->begin(); it != in_pos_list->end(); it++) {
	    pos_list->push_back(*it);
	}

	return true;
    }
}

std::vector<int> *Document::get_pos() {
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
