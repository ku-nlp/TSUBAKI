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


def main():
    oparser = optparse.OptionParser()
    oparser.add_option("-i", "--input", dest="input", default="-")
    oparser.add_option("-o", "--output", dest="output", default="-")
    oparser.add_option(
        "--verbose", dest="verbose", action="store_true", default=False)
    (opts, args) = oparser.parse_args()

    if opts.input == "-":
        inf = sys.stdin
    else:
        inf = codecs.open(opts.input, "r", "utf8")

    if opts.output == "-":
        outf = sys.stdout
    else:
        outf = codecs.open(opts.output, "w", "utf8")

    sum = 0
    for line in inf:
        count = int(line[line.rfind(u"\t"):-1])
        print u"%s\t%s" % (line[:-1], sum)
        sum += count

if __name__ == '__main__':
    main()
