"""utilities to assist in working with pygit2"""
from __future__ import absolute_import

from mercurial.node import bin, hex, nullid

from mercurial import pycompat


def togitnode(n):
    """Wrapper to convert a Mercurial binary node to a unicode hexlified node.

    pygit2 and sqlite both need nodes as strings, not bytes.
    """
    assert len(n) == 20
    return pycompat.sysstr(hex(n))


def fromgitnode(n):
    """Opposite of togitnode."""
    assert len(n) == 40
    if pycompat.ispy3:
        return bin(n.encode('ascii'))
    return bin(n)


nullgit = togitnode(nullid)
