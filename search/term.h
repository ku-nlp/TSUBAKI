#ifndef TERM_H
#define TERM_H

using std::cout;

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

#endif
