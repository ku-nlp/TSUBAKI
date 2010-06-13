#include "common.h"
#include "document.h"

std::string Document::to_string () {
    if (best_begin < 0) {
	best_begin = (int)(best_pos - 0.5 * PROXIMATE_LENGTH);
	best_end   = (int)(best_pos + 0.5 * PROXIMATE_LENGTH);
    }

    std::ostringstream _str;
    _str << id << " " << get_final_score() << " " << best_begin << " " << best_end;

    return _str.str();
}

bool Document::set_term_pos(std::string term, std::vector<int> &in_pos_list) {
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
