#include "Mapper.hpp"
#include <iostream>
#include <stdexcept>
#include <assert.h>
#include <algorithm>


typedef Mapper::Span Span;

struct CompWithEnd {
	bool operator()(const Span &s, unsigned n) const { return s.second < n; }
	bool operator()(unsigned n, const Span &s) const { return n < s.second; }
};

struct CompWithBegin {
	bool operator()(const Span &s, unsigned n) const { return s.first < n; }
	bool operator()(unsigned n, const Span &s) const { return n < s.first; }
};

Mapper::SearchRegion
Mapper::getInitialSearchRegion(void) const
{
	return SearchRegion(domain.begin(), domain.end());
}

class OutOfDomainAnnotation : public std::runtime_error {
public:
	OutOfDomainAnnotation(void)
		: std::runtime_error("annotation in the outside of the text") {};
};

inline
bool
contains(const Span &s, unsigned int n)
{
	return s.first <= n && n <= s.second;
}

inline
unsigned int
doMapping(const Span &domain, const Span &range, unsigned int n)
{
	assert(contains(domain, n));

	return range.first + (n - domain.first);
}

Mapper::SearchRegion
Mapper::map(
	SearchRegion emptyTagRegion,
	const Span &in,
	Span &out
) const {

	if (in.first == in.second) { /// empty tag

		SpanVecItr searchBegin = emptyTagRegion.first;
		SpanVecItr searchEnd = emptyTagRegion.second;

		SpanVecItr domItr = std::lower_bound(
			searchBegin, searchEnd, in.second, CompWithEnd());

		/// this empty tag is to the right of the last non-empty tag
		if (domItr == searchEnd) {

			domItr = std::lower_bound(
				searchBegin, domain.end(), in.second, CompWithEnd());

			if (domItr == domain.end()) {
				throw OutOfDomainAnnotation();
			}
		}

		const Span &r = range[std::distance(domain.begin(), domItr)];

		out.first = doMapping(*domItr, r, in.first);
		out.second = out.first;

		/// avoid redundant search in the case of continuous empty tags
		return SearchRegion(domItr, domItr + 1);
	}
	else { /// non-empty tag

		SpanVecItr domFirst = std::upper_bound(
			domain.begin(), domain.end(), in.first, CompWithBegin());

		if (domFirst == domain.begin()) {
			/// this case should never occur except for the case where
			/// the clipped document is empty because the domain
			/// vector contain at least one element starting from 0.
			throw OutOfDomainAnnotation();
		}

		--domFirst;
		if (! contains(*domFirst, in.first)) {
			/// this should never occur. same reason as above.
			throw OutOfDomainAnnotation();
		}

		SpanVecItr domSecond = std::lower_bound(
			domain.begin(), domain.end(), in.second, CompWithEnd());

		if (domSecond == domain.end() || ! contains(*domSecond, in.second)) {
			throw OutOfDomainAnnotation();
		}

		const Span &rangeFirst = range[std::distance(domain.begin(), domFirst)];
		const Span &rangeSecond
			= range[std::distance(domain.begin(), domSecond)];

		out.first = doMapping(*domFirst, rangeFirst, in.first);
		out.second = doMapping(*domSecond, rangeSecond, in.second);

		return SearchRegion(domFirst, domSecond);
	}
}

void
Mapper::setClippingSpan(const Span &s)
{
	unsigned start = s.first;
	unsigned end = s.second;

	unsigned length = end - start;

	if (domain.empty()) {

		assert(range.empty());

		domain.push_back(Span(0, length));
		range.push_back(Span(start, end));

		return;
	}

	unsigned rangeLast = range.back().second;

	if (rangeLast < start) {

		unsigned domainLast = domain.back().second;

		/// TODO: change the clipping mechanism and remove this peculiar shift 
		domain.push_back(Span(domainLast + 1, domainLast + 1 + length));
		range.push_back(Span(start, end));
	}
	else if (rangeLast < end) {

		if (start < range.back().first) {
			throw std::runtime_error(
                "som::Mapper: input tags are not properly ordered");
		}

		unsigned diff = end - rangeLast;

		domain.back().second += diff;
		range.back().second += diff;
	}
}
