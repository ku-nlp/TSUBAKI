#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
"""
__author__ = 'Yuta Hayashibe'
__version__ = ""
__copyright__ = ""
__license__ = "GPL v3"


import codecs
import sys
sys.stdin = codecs.getreader('UTF-8')(sys.stdin)
sys.stdout = codecs.getwriter('UTF-8')(sys.stdout)
sys.stderr = codecs.getwriter('UTF-8')(sys.stderr)


import optparse


import zipfile
def main():
    for fname in sys.argv[1:]:
        try:
            z= zipfile.ZipFile(fname, "r")
            print u"%s\t%d" % (fname, len(z.infolist()))
        except: #broken zip
            pass

if __name__ == '__main__':
    main()
