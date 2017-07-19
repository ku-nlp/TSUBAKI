#!/usr/bin/env python
# -*- coding: utf-8 -*-

# sixが必要 (pip install six)

from __future__ import print_function
import sys
import six
import io
import codecs
from six.moves.urllib.parse import urlparse, urlencode, quote
from six.moves.urllib.request import urlopen
from six.moves.urllib.error import HTTPError

# このアドレスを変更して下さい
base_url = "http://tsubaki.ixnlp.nii.ac.jp/cgi/api.cgi"
    
def main():
    query = u"京大"
    uri_escaped_query = quote(query.encode("utf-8"))
    results = 20
    start = 1
   
    # リクエストURLを作成
    req_url = "%s?query=%s&results=%d&start=%d" % (base_url, uri_escaped_query, results, start)

    try:
        r = urlopen(req_url)
        response = r.read()
        print(response.decode("utf-8"))
    except HTTPError as e:
        print(e.code)
        print(e.reason)

        print(e.read())
    
if __name__ == "__main__":
    if six.PY3:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    else:
        sys.stdout = codecs.getwriter('UTF-8')(sys.stdout)

    main()


