#include "common.h"
#include "document.h"

std::string Document::to_string() {
    std::ostringstream _str;
    _str << id << " "
	 << get_final_score() << " "
	 << get_length() << " "
	 << get_pagerank() << " "
	 << get_strict_term_feature() << " "
	 << get_proximate_feature() << " "
	 << best_begin << " "
	 << best_end << " [";
    for (std::vector<Term*>::iterator it = terms.begin(); it != terms.end(); it++) {
	_str << (*it)->to_string() << ",";
    }
    _str << "]";

    _str << " [";
    for (std::vector<Term*>::iterator it = terms.begin(); it != terms.end(); it++) {
	_str << (*it)->get_term();
        std::vector<int> *pos_list_ptr = (*it)->get_pos_list();
	for (std::vector<int>::iterator _it = pos_list_ptr->begin(); _it != pos_list_ptr->end(); _it++) {
	    if ((*_it) == -1) break;
	    _str << "," << (*_it);
	}
	_str << "#";
    }
    _str << "]";

    return _str.str();
}

bool Document::set_term_pos(std::string term, std::vector<int> const *in_pos_list, std::vector<double> const *in_score_list) {
    if (pos_list == in_pos_list) { // do nothing if input is the pointer of this->pos_list
	return true;
    }
    else {
        // delete pos_list if available
        delete pos_list;

        pos_list = new std::vector<int>(*in_pos_list);

        delete score_list;
        if (in_score_list)
            score_list = new std::vector<double>(*in_score_list);
        else
            score_list = NULL;

	return true;
    }
}

std::vector<int> *Document::get_pos(unsigned int featureBit) {
    if (pos_list == NULL) {
	pos_list = new std::vector<int>;
	if (pos_buf) {
            score_list = new std::vector<double>;
            unsigned char *pos_buf_ptr = pos_buf;
	    score = 0;
	    pos_num = intchar2int(pos_buf_ptr);
            pos_list->reserve(pos_num + 1);
	    pos_buf_ptr += sizeof(int);

	    freq = 0;
	    for (int i = 0; i < pos_num; i++) {
		unsigned int feature = intchar2int(pos_buf_ptr);
		pos_buf_ptr += sizeof(int);
                // no features are given or feature matches featureBit
		if (featureBit == 0 || (feature & featureBit & CONDITION_FEATURE_MASK)) {
		    int posfreq = intchar2int(pos_buf_ptr);
		    double frq = 0.001 * (posfreq & FREQ_MASK);
		    int pos = posfreq >> FREQ_BIT_SIZE;
		    pos_list->push_back(pos);
		    double weight = 1.0;
                    if (!retrieved_by_basic_node && !retrieved_by_dpnd_node) // synnode
                        weight *= WEIGHT_OF_SYN_NODE;
                    if (retrieved_by_dpnd_node)
                        weight *= WEIGHT_OF_DPND_NODE;
                    if (featureBit & CASE_FEATURE_MASK) { // case feature is specified in query
                        if (feature & featureBit & CASE_FEATURE_MASK)
                            weight *= WEIGHT_OF_CASE_FEATURE_MATCH;
                    }
                    if (featureBit > 0) {
                        if ((featureBit & DPND_TYPE_FEATURE_MASK) != (feature & DPND_TYPE_FEATURE_MASK))
                            weight *= WEIGHT_OF_DPND_TYPE_FEATURE_MISMATCH;
                    }

                    double cur_freq = weight * frq;
		    score_list->push_back(cur_freq);
		    freq += cur_freq;
		}
		pos_buf_ptr += sizeof(int);
	    }
	    pos_list->push_back(-1);
	    score = calc_okapi(freq);

            // shrink_to_fit
            // std::vector<int>(*pos_list).swap(*pos_list);
	}
        else {
            pos_num = 0;
	    pos_list->push_back(-1);
        }
    }

    return pos_list;
}
