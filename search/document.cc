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
    for (MAP_IMPL<const char*, std::vector<int> *>::iterator it = term2pos.begin(); it != term2pos.end(); it++) {
	_str << it->first;
	for (std::vector<int>::iterator _it = it->second->begin(); _it != it->second->end(); _it++) {
	    if ((*_it) == -1) break;
	    _str << "," << (*_it);
	}
	_str << "#";
    }
    _str << "]";

    return _str.str();
}

bool Document::set_term_pos(std::string term, std::vector<int> const *in_pos_list) {
    if (pos_list == in_pos_list) { // do nothing if input is the pointer of this->pos_list
	return true;
    }
    else {
        // delete pos_list if available
        delete pos_list;

        pos_list = new std::vector<int>(*in_pos_list);
	return true;
    }
}

std::vector<int> *Document::get_pos(unsigned int featureBit) {
    if (pos_list == NULL) {
	pos_list = new std::vector<int>;
	if (pos_buf) {
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
                    if (featureBit > 0) {
                        if (!(featureBit & CASE_FEATURE_MASK))
                            weight *= WEIGHT_OF_CASE_FEATURE_MISMATCH;

                        if (!(featureBit & DPND_TYPE_FEATURE_MASK))
                            weight *= WEIGHT_OF_DPND_TYPE_FEATURE_MISMATCH;
                    }

		    freq += (weight * frq);
		}
		pos_buf_ptr += sizeof(int);
	    }
	    pos_list->push_back(-1);
	    score = calc_okapi(freq, gdf);

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
