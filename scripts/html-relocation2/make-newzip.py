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


def get_gid(myid):
    gid = int(myid / 10000)
    return gid

def get_idx(myid):
    return int(myid % 10000)

import os
def mkdirp(path):
    try:
        os.makedirs(path)
    except OSError:
        pass

import os
import zipfile
def get_blank_zout(outdir, gid):
    fname = u"%06d.zip" % gid
    mkdirp(os.path.join(outdir, fname[:4]))
    fpath =  os.path.join(outdir, fname[:4], fname)
    return zipfile.ZipFile(fpath, 'w')

import zipfile
def operation(inf, outdir, target, num):
    zout = None
    zout_gid = None
    for line in inf:
        items = line[:-1].split(u"\t")
        ifname = items[0]
        fnum = int(items[1])
        start_id = int(items[2])
        last_id  = start_id + fnum -1

        start_gid = get_gid(start_id)
        last_gid = get_gid(last_id)
        if not(target <= start_gid < target + num) and \
                not(target <= last_gid < target + num):
            continue

        ###do
        z = zipfile.ZipFile(ifname, "r")
        zinfo = z.infolist()
        for i, myid in enumerate(xrange(start_id, start_id + fnum)):
            mygid = get_gid(myid)
            myidx = get_idx(myid)
            if mygid < target or mygid >= target + num:
                continue

            if (zout is not None) and (zout_gid != mygid):
                zout.close()
                zout = None

            if zout is None:
                zout = get_blank_zout(outdir, mygid)
                zout_gid = mygid

            myfname = u"%010d.html.gz" % myid
            myinfo = zipfile.ZipInfo(os.path.join(myfname[:6], myfname))
            myinfo.external_attr = 0644 << 16L
            zout.writestr(myinfo, z.read(zinfo[i]))
#             print myid, mygid, myidx, zinfo[i]
        z.close()
    if zout is not None:
        zout.close()


import optparse
def main():
    oparser = optparse.OptionParser()
    oparser.add_option("-i", "--input", dest="input", default="-")
    oparser.add_option("-o", "--output", dest="output", default=None)
    oparser.add_option("-t", "--target", dest="target", type="int", default=0)
    oparser.add_option("-n", "--num", dest="num", type="int", default=1)
    oparser.add_option(
        "--verbose", dest="verbose", action="store_true", default=False)
    (opts, args) = oparser.parse_args()

    if opts.input == "-":
        inf = sys.stdin
    else:
        inf = codecs.open(opts.input, "r", "utf8")

    if opts.output is None:
        raise

    operation(inf, opts.output, opts.target, opts.num)

if __name__ == '__main__':
    main()
