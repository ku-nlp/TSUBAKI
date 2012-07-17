#ifndef TERM_H
#define TERM_H

class Term {
    std::string term;
    double freq;
    double score;
    int gdf;
    std::vector<int> pos_list;

  public:
    Term(std::string *_term, double _score, double _freq, int _gdf, std::vector<int> *_pos_list) {
	term = (*_term);
	score = _score;
	freq = _freq;
	gdf = _gdf;
        if (_pos_list)
            pos_list = *_pos_list;
    }

    std::string to_string() {
	std::ostringstream _str;
	_str << term << " " << score << " " << freq << " " << gdf;
	return _str.str();
    }

    std::string &get_term() {
	return term;
    }

    std::vector<int> *get_pos_list() {
	return &pos_list;
    }
};

#endif
