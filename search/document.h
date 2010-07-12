#ifndef DOCUMENT_H
#define DOCUMENT_H

#include "term.h"

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
    double pagerank;
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

    std::string to_string ();

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
    bool set_term_pos(std::string term, std::vector<int> &in_pos_list);
    std::vector<int> *get_pos();

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

    bool set_pagerank (double _pagerank) {
	pagerank = _pagerank;
    }

    double get_final_score() {
	double _score = get_score();
	double tsubakiScore = _score + (WEIGHT_OF_STRICT_TERM_F * strict_term_feature) + (WEIGHT_OF_PROXIMATE_F * proximate_feature);
	double pagerankScore = (-1 * C_PAGERANK) / log(pagerank);
	return (WEIGHT_OF_TSUBAKI_SCORE * tsubakiScore) + ((1 - WEIGHT_OF_TSUBAKI_SCORE) * pagerankScore);
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

#endif
