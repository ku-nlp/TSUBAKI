#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
"""
__author__ = 'Yuta Hayashibe'
__version__ = ""
__copyright__ = ""
__license__ = "GPL v3"


import optparse
import codecs
import sys
sys.stdin = codecs.getreader('UTF-8')(sys.stdin)
sys.stdout = codecs.getwriter('UTF-8')(sys.stdout)
sys.stderr = codecs.getwriter('UTF-8')(sys.stderr)


def operation(source, num, servers, to, bwlimit, outconf):
    assert isinstance(bwlimit, int)
    assert isinstance(num, int)
    assert isinstance(servers, list)

    print "gxpc e mkdir -p %s" % to
    for i in xrange(0, num + 1, 1):
        myserver = servers[i % len(servers)]
        my_snippet_server = servers[(i + 1) % len(servers)]
        command = u"rsync " + \
            u" --include '%04d' " % i +\
            u" --include 'sid2tid' --include '*.cdb*' " +\
            u" --include 'doc_length.txt' --include 'idx.*.dat' --exclude '*' " +\
            u" --bwlimit=%d -e 'ssh -c arcfour' -av %s/%04d %s" % (bwlimit, source, i, to)
        print """ gxpc e " (hostname | grep %s > /dev/null )  &&  %s"  """ % (myserver, command)
        if outconf is not None:
            out1 = u"SNIPPET_SERVERS\t%s\t%s\t%04d" % (my_snippet_server, 60000 + i, i)
            out2 = u"SEARCH_SERVERS\t%s\t%s\t%s/%04d\t%s" % (myserver, 40000 + i, to, i, u"none")
            outconf.write(out1)
            outconf.write(u"\n")
            outconf.write(out2)
            outconf.write(u"\n")


def main():
    oparser = optparse.OptionParser()
    oparser.add_option("-i", "--input", dest="input", default="-", help="The file with server names")
    oparser.add_option("-s", "--source", dest="source", default=None)
    oparser.add_option("-t", "--to", dest="to", default=None)
    oparser.add_option("-n", "--num", dest="num", type="int", default=None)
    oparser.add_option("-c", "--conf", dest="conf", default=None)
    oparser.add_option("--bwlimit", dest="bwlimit", type="int", default=(1024 * 50))
    (opts, args) = oparser.parse_args()

    if opts.source is None:
        sys.stderr.write(u"No --source\n")
        sys.exit(1)
    if opts.num is None:
        sys.stderr.write(u"No --num\n")
        sys.exit(1)
    if opts.to is None:
        sys.stderr.write(u"No --to\n")
        sys.exit(1)

    if opts.input == "-":
        inf = sys.stdin
    else:
        inf = codecs.open(opts.input, "r", "utf8")
    servers = [name.strip() for name in inf.readlines()]

    outconf = None
    if opts.conf is not None:
        outconf = codecs.open(opts.conf, "w", "utf8")
    operation(opts.source, opts.num, servers, opts.to, opts.bwlimit, outconf)
    if outconf is not None:
        outconf.close()


if __name__ == '__main__':
    main()
