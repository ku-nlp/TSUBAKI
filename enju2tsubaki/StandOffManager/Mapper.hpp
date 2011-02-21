#ifndef MAPPER_HPP
#define MAPPER_HPP

#include <vector>
#include <utility>
#include <string>

#include "TagData.hpp"

class Mapper{
public:
	typedef TagData::Span Span;
	typedef std::vector<Span> SpanVec;
	typedef SpanVec::const_iterator SpanVecItr;
	typedef std::pair<SpanVecItr, SpanVecItr> SearchRegion;

    void setClippingSpan(const Span &s);

	SearchRegion map(
		SearchRegion emptyTagRegion,
		const Span &in,
		Span &out) const;

	SearchRegion getInitialSearchRegion(void) const;

private:
    SpanVec domain;
    SpanVec range;
};

#endif /*MAPPER_HPP*/
