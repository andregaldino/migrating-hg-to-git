# revlogutils/debug.py - utility used for revlog debuging
#
# Copyright 2005-2007 Olivia Mackall <olivia@selenic.com>
# Copyright 2022 Octobus <contact@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from .. import (
    node as nodemod,
)


def debug_index(
    ui,
    repo,
    formatter,
    revlog,
    full_node,
):
    """display index data for a revlog"""
    if full_node:
        hexfn = nodemod.hex
    else:
        hexfn = nodemod.short

    idlen = 12
    for i in revlog:
        idlen = len(hexfn(revlog.node(i)))
        break

    fm = formatter

    fm.plain(
        b'   rev linkrev %s %s %s\n'
        % (b'nodeid'.rjust(idlen), b'p1'.rjust(idlen), b'p2'.rjust(idlen))
    )

    for rev in revlog:
        node = revlog.node(rev)
        parents = revlog.parents(node)

        fm.startitem()
        fm.write(b'rev', b'%6d ', rev)
        fm.write(b'linkrev', b'%7d ', revlog.linkrev(rev))
        fm.write(b'node', b'%s ', hexfn(node))
        fm.write(b'p1', b'%s ', hexfn(parents[0]))
        fm.write(b'p2', b'%s', hexfn(parents[1]))
        fm.plain(b'\n')

    fm.end()
