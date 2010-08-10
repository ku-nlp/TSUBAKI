#ifndef TERM_H
#define TERM_H

using std::cout;

class Term {
    std::string term;
    double freq;
    double score;
    int gdf;

  public:
    Term (std::string *_term, double _score, double _freq, int _gdf) {
	term = (*_term);
	score = _score;
	freq = _freq;
	gdf  = _gdf;
    }

    std::string to_string () {
	std::ostringstream _str;
	_str << term << " " << score << " " << freq << " " << gdf;
	return _str.str();
    }
};

#endif
