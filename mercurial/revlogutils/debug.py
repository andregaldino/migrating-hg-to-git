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

from . import (
    constants,
)

INDEX_ENTRY_DEBUG_COLUMN = []

NODE_SIZE = object()


class _column_base:
    """constains the definition of a revlog column

    name:         the column header,
    value_func:   the function called to get a value,
    size:         the width of the column,
    verbose_only: only include the column in verbose mode.
    """

    def __init__(self, name, value_func, size=None, verbose=False):
        self.name = name
        self.value_func = value_func
        if size is not NODE_SIZE:
            if size is None:
                size = 8  # arbitrary default
            size = max(len(name), size)
        self._size = size
        self.verbose_only = verbose

    def get_size(self, node_size):
        if self._size is NODE_SIZE:
            return node_size
        else:
            return self._size


def debug_column(name, size=None, verbose=False):
    """decorated function is registered as a column

    name: the name of the column,
    size: the expected size of the column.
    """

    def register(func):
        entry = _column_base(
            name=name,
            value_func=func,
            size=size,
            verbose=verbose,
        )
        INDEX_ENTRY_DEBUG_COLUMN.append(entry)
        return entry

    return register


@debug_column(b"rev", size=6)
def _rev(index, rev, entry, hexfn):
    return b"%d" % rev


@debug_column(b"linkrev", size=6)
def _linkrev(index, rev, entry, hexfn):
    return b"%d" % entry[constants.ENTRY_LINK_REV]


@debug_column(b"nodeid", size=NODE_SIZE)
def _nodeid(index, rev, entry, hexfn):
    return hexfn(entry[constants.ENTRY_NODE_ID])


@debug_column(b"p1-nodeid", size=NODE_SIZE)
def _p1_node(index, rev, entry, hexfn):
    parent = entry[constants.ENTRY_PARENT_1]
    p_entry = index[parent]
    return hexfn(p_entry[constants.ENTRY_NODE_ID])


@debug_column(b"p2-nodeid", size=NODE_SIZE)
def _p2_node(index, rev, entry, hexfn):
    parent = entry[constants.ENTRY_PARENT_2]
    p_entry = index[parent]
    return hexfn(p_entry[constants.ENTRY_NODE_ID])


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

    header_pieces = []
    for column in INDEX_ENTRY_DEBUG_COLUMN:
        if column.verbose_only and not ui.verbose:
            continue
        size = column.get_size(idlen)
        name = column.name
        header_pieces.append(name.rjust(size))

    fm.plain(b' '.join(header_pieces) + b'\n')

    index = revlog.index

    for rev in revlog:
        fm.startitem()
        entry = index[rev]
        first = True
        for column in INDEX_ENTRY_DEBUG_COLUMN:
            if column.verbose_only and not ui.verbose:
                continue
            if not first:
                fm.plain(b' ')
            first = False

            size = column.get_size(idlen)
            value = column.value_func(index, rev, entry, hexfn)
            display = b"%%%ds" % size
            fm.write(column.name, display, value)
        fm.plain(b'\n')

    fm.end()
