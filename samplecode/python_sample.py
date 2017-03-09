#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import codecs
import urllib2

def main():
    query = u"京都の観光名所"
    uri_escaped_query = urllib2.quote(query.encode("utf-8"))
    results = 20
    start = 1

    base_url = "http://tsubaki.ixnlp.nii.ac.jp/api.cgi"
    
    # リクエストURLを作成
    req_url = "%s?query=%s&results=%d&start=%d" % (base_url, uri_escaped_query, results, start)

    try:
        r = urllib2.urlopen(req_url)
        response = r.read()
        print response.decode("utf-8")
    except urllib2.HTTPError, e:
        print e.code
        print e.reason

        print e.read()
    
if __name__ == "__main__":
    sys.stdin  = codecs.getreader('UTF-8')(sys.stdin)
    sys.stdout = codecs.getwriter('UTF-8')(sys.stdout)

    main()


