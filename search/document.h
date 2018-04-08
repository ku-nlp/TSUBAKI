#ifndef DOCUMENT_H
#define DOCUMENT_H

#include "term.h"

#define OKAPI_K1 1
#define OKAPI_B 0.6

class Document {
    int id;
    int length;
    int pos_num;
    int strict_term_feature;
    int proximate_feature;
    int phrase_feature;
    int best_pos;
    int best_begin;
    int best_end;
    double freq;
    double gdf;
    double score;
    double pagerank;
    unsigned char *pos_buf;
    bool retrieved_by_basic_node;
    bool retrieved_by_dpnd_node;
    bool retrieved_by_dpnd_node_with_case_match;

    std::vector<int> *pos_list;
    std::vector<double> *score_list;
    std::vector<unsigned int> *num_of_phrases_list;
    std::vector<double> *gdf_list;
    std::vector<Term *> terms;
  public:
    Document(int in_id) {
	id = in_id;
	score = -1;
	length = 10;
	best_pos = -1;
	best_begin = -1;
	best_end = -1;
	freq = -1;
	gdf = -1;
        retrieved_by_basic_node = false;
        retrieved_by_dpnd_node = false;
        retrieved_by_dpnd_node_with_case_match = false;

	proximate_feature = 0;
	strict_term_feature = 0;
	phrase_feature = 0;
	pos_list = NULL;
	score_list = NULL;
	pos_buf = NULL;
    }

    ~Document() {
        delete pos_list;
        if (pos_buf)
            free(pos_buf);
    }

    int get_id() const {
	return id;
    }

    int get_pos_num() const {
	return pos_num;
    }

    bool set_best_pos(int pos) {
	best_pos = pos;
	return true;
    }

    int get_best_pos() const {
	return best_pos;
    }

    bool set_best_region(int begin, int end) {
	best_begin = begin;
	best_end = end;
	return true;
    }

    bool set_pos_char(unsigned char *pos_char) {
	pos_buf = pos_char;
	return true;
    }

    std::string to_string();

    bool set_length(int in_length) {
      length = in_length;
      return true;
    }

    int get_length() const {
	return length;
    }

    bool set_proximate_feature() {
      proximate_feature = 1;
      return true;
    }

    bool get_proximate_feature() const {
      return proximate_feature;
    }

    bool set_strict_term_feature() {
      strict_term_feature = 1;
      return true;
    }

    bool get_strict_term_feature() const {
      return strict_term_feature;
    }

    bool set_phrase_feature() {
      phrase_feature = 1;
      return true;
    }

    bool get_phrase_feature() const {
	return phrase_feature;
    }

    bool calc_score();
    bool set_term_pos(std::string term, std::vector<int> const *in_pos_list, std::vector<double> const *in_score_list, std::vector<unsigned int> const *in_num_of_phrases_list, std::vector<double> const *in_gdf_list);
    std::vector<int> *get_pos(unsigned int featureBit, unsigned int num_of_phrases);

    std::vector<double> *get_score_list() {
        return score_list;
    }

    std::vector<unsigned int> *get_num_of_phrases_list() {
        return num_of_phrases_list;
    }

    std::vector<double> *get_gdf_list() {
        return gdf_list;
    }

    bool set_freq(double in_freq) {
	freq = in_freq;

	return true;
    }
    double get_freq() const {
	return freq;
    }
    bool set_gdf(double in_gdf) {
	gdf = in_gdf;
	return true;
    }
    double get_gdf() const {
	return gdf;
    }
    bool set_score(double in_score) {
	score = in_score;
	return true;
    }

    bool set_pagerank(double _pagerank) {
	pagerank = _pagerank;
	return true;
    }

    double get_pagerank() const {
	return pagerank;
    }

    double get_final_score() {
	double _score = get_score();
	double tsubakiScore = _score + (WEIGHT_OF_STRICT_TERM_F * strict_term_feature) + (WEIGHT_OF_PROXIMATE_F * proximate_feature);
	double pagerankScore = C_PAGERANK * pagerank;
	return (WEIGHT_OF_TSUBAKI_SCORE * tsubakiScore) + ((1 - WEIGHT_OF_TSUBAKI_SCORE) * pagerankScore);
    }

    double get_score() {
	if (score < 0) {
	    return calc_okapi(freq, gdf);
	} else {
	    return score;
	}
    }
    double calc_okapi(double in_freq) {
        return calc_okapi(in_freq, gdf);
    }
    double calc_okapi(double in_freq, double in_gdf) {
	if (freq < 0) {
	    score = 0;
	} else {
	    double tf = ((OKAPI_K1 + 1) * in_freq) / (OKAPI_K1 * ((1 - OKAPI_B) + OKAPI_B * length / AVERAGE_DOC_LENGTH) + in_freq);
	    double idf = log((TOTAL_NUMBER_OF_DOCS - in_gdf + 0.5) / (in_gdf + 0.5));
	    score = tf * idf;
	}
	return score;
    }

    bool pushbackTerm(Term *term) {
	terms.push_back(term);
	return true;
    }

    std::vector<Term *>* getTerms() {
	return &terms;
    }

    void set_retrieved_by_basic_node(bool flag) {
	retrieved_by_basic_node = flag;
    }
    bool get_retrieved_by_basic_node() {
	return retrieved_by_basic_node;
    }

    void set_retrieved_by_dpnd_node(bool flag) {
	retrieved_by_dpnd_node = flag;
    }
    bool get_retrieved_by_dpnd_node() {
	return retrieved_by_dpnd_node;
    }

    void set_match_dpnd_node_with_case(bool flag) {
	retrieved_by_dpnd_node_with_case_match = flag;
    }
    bool get_match_dpnd_node_with_case() {
	return retrieved_by_dpnd_node_with_case_match;
    }

    bool print() {
        std::cout << " " << id; // << ":";
	// for (std::vector<Term *>::iterator it = terms.begin(); it != terms.end(); it++) {
	//     (*it)->print();
	// }
	return true;
    }
};

#endif
