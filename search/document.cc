#include "common.h"
#include "document.h"

std::string Document::to_string() {
    std::ostringstream _str;
    _str << id << "\t" << get_final_score() << "\t" << get_length() << "\t"
         << get_pagerank() << "\t" << get_strict_term_feature() << "\t"
         << get_proximate_feature() << "\t" << best_begin << "\t" << best_end
         << "\t[";
    for (std::vector<Term *>::iterator it = terms.begin(); it != terms.end();
         it++) {
        _str << (*it)->to_string() << ",";
    }
    _str << "]";

    _str << " [";
    for (std::vector<Term *>::iterator it = terms.begin(); it != terms.end();
         it++) {
        _str << (*it)->get_term();
        std::vector<int> *pos_list_ptr = (*it)->get_pos_list();
        std::vector<unsigned int> *num_of_phrases_list_ptr = (*it)->get_num_of_phrases_list();
        int i = 0;
        for (std::vector<int>::iterator _it = pos_list_ptr->begin();
             _it != pos_list_ptr->end(); _it++) {
            if ((*_it) == -1)
                break;
            _str << "," << (*_it) << ":" << num_of_phrases_list_ptr->at(i);
            i++;
        }
        _str << "#";
    }
    _str << "]";

    return _str.str();
}

bool Document::set_term_pos(std::string term,
                            std::vector<int> const *in_pos_list,
                            std::vector<double> const *in_score_list,
                            std::vector<unsigned int> const *in_num_of_phrases_list,
                            std::vector<double> const *in_gdf_list,
                            std::vector<std::string> const *in_term_list) {
    // do nothing if input is the pointer of this->pos_list
    if (pos_list != in_pos_list) {
        // delete pos_list if available
        delete pos_list;
        pos_list = new std::vector<int>(*in_pos_list);
    }

    if (score_list != in_score_list) {
        delete score_list;
        if (in_score_list)
            score_list = new std::vector<double>(*in_score_list);
        else
            score_list = NULL;
    }

    if (num_of_phrases_list != in_num_of_phrases_list) {
        delete num_of_phrases_list;
        if (num_of_phrases_list)
            num_of_phrases_list = new std::vector<unsigned int>(*in_num_of_phrases_list);
        else
            num_of_phrases_list = NULL;
    }

    if (gdf_list != in_gdf_list) {
        delete gdf_list;
        if (in_gdf_list)
            gdf_list = new std::vector<double>(*in_gdf_list);
        else
            gdf_list = NULL;
    }

    if (term_list != in_term_list) {
        delete term_list;
        if (in_term_list)
            term_list = new std::vector<std::string>(*in_term_list);
        else
            term_list = NULL;
    }
    return true;
}

std::vector<int> *Document::get_pos(unsigned int featureBit, unsigned int num_of_phrases) {
    if (pos_list == NULL) {
        pos_list = new std::vector<int>;
        if (pos_buf) {
            score_list = new std::vector<double>;
            num_of_phrases_list = new std::vector<unsigned int>;
            gdf_list = new std::vector<double>;
            term_list = new std::vector<std::string>;
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
                if (!(featureBit & CONDITION_FEATURE_MASK) ||
                    (feature & featureBit & CONDITION_FEATURE_MASK)) {
                    int posfreq = intchar2int(pos_buf_ptr);
                    double frq = 0.001 * (posfreq & FREQ_MASK);
                    int pos = posfreq >> FREQ_BIT_SIZE;
                    pos_list->push_back(pos);
                    double weight = 1.0;
                    if (!retrieved_by_basic_node &&
                        !retrieved_by_dpnd_node) // synnode
                        weight *= WEIGHT_OF_SYN_NODE;
                    if (retrieved_by_dpnd_node)
                        weight *= WEIGHT_OF_DPND_NODE;
                    if (featureBit & CASE_FEATURE_MASK) { // case feature is
                                                          // specified in query
                        if (feature & featureBit & CASE_FEATURE_MASK) {
                            set_match_dpnd_node_with_case(true);
                            weight *= WEIGHT_OF_CASE_FEATURE_MATCH;
#ifdef DEBUG
                            std::cerr
                                << "Case feature match! : "
                                << (feature & featureBit & CASE_FEATURE_MASK)
                                << std::endl;
#endif
                        }
#ifdef DEBUG
                        else
                            std::cerr << "Case feature mismatch!" << std::endl;
#endif
                    }
                    if (featureBit > 0) {
                        if ((featureBit & DPND_TYPE_FEATURE_MASK) !=
                            (feature & DPND_TYPE_FEATURE_MASK)) {
                            std::cerr << (featureBit & DPND_TYPE_FEATURE_MASK)
                                      << " : "
                                      << (feature & DPND_TYPE_FEATURE_MASK)
                                      << std::endl;
                            weight *= WEIGHT_OF_DPND_TYPE_FEATURE_MISMATCH;
                        }
                    }

                    double cur_freq = weight * frq;
                    if (NO_USE_TF_MODE)
                        cur_freq = cur_freq / pos_num;
		    score_list->push_back(cur_freq);
                    num_of_phrases_list->push_back(num_of_phrases);
                    gdf_list->push_back(gdf);
                    term_list->push_back(term);
                    freq += cur_freq;
                }
                pos_buf_ptr += sizeof(int);
            }
            pos_list->push_back(-1);
            score = calc_okapi(freq);
            // multiply num_of_phrases to strengthen a synnode term consisting of multiple phrases
            if (num_of_phrases > 1)
                score *= sqrt(num_of_phrases);

            // shrink_to_fit
            // std::vector<int>(*pos_list).swap(*pos_list);
        } else {
            pos_num = 0;
            pos_list->push_back(-1);
        }
    }

    return pos_list;
}
