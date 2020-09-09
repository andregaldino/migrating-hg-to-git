# grep.py - logic for history walk and grep
#
# Copyright 2005-2007 Matt Mackall <mpm@selenic.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import difflib

from . import pycompat


def matchlines(body, regexp):
    begin = 0
    linenum = 0
    while begin < len(body):
        match = regexp.search(body, begin)
        if not match:
            break
        mstart, mend = match.span()
        linenum += body.count(b'\n', begin, mstart) + 1
        lstart = body.rfind(b'\n', begin, mstart) + 1 or begin
        begin = body.find(b'\n', mend) + 1 or len(body) + 1
        lend = begin - 1
        yield linenum, mstart - lstart, mend - lstart, body[lstart:lend]


class linestate(object):
    def __init__(self, line, linenum, colstart, colend):
        self.line = line
        self.linenum = linenum
        self.colstart = colstart
        self.colend = colend

    def __hash__(self):
        return hash(self.line)

    def __eq__(self, other):
        return self.line == other.line

    def findpos(self, regexp):
        """Iterate all (start, end) indices of matches"""
        yield self.colstart, self.colend
        p = self.colend
        while p < len(self.line):
            m = regexp.search(self.line, p)
            if not m:
                break
            if m.end() == p:
                p += 1
            else:
                yield m.span()
                p = m.end()


def difflinestates(a, b):
    sm = difflib.SequenceMatcher(None, a, b)
    for tag, alo, ahi, blo, bhi in sm.get_opcodes():
        if tag == 'insert':
            for i in pycompat.xrange(blo, bhi):
                yield (b'+', b[i])
        elif tag == 'delete':
            for i in pycompat.xrange(alo, ahi):
                yield (b'-', a[i])
        elif tag == 'replace':
            for i in pycompat.xrange(alo, ahi):
                yield (b'-', a[i])
            for i in pycompat.xrange(blo, bhi):
                yield (b'+', b[i])
