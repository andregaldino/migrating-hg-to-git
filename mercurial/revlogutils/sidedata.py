# sidedata.py - Logic around store extra data alongside revlog revisions
#
# Copyright 2019 Pierre-Yves David <pierre-yves.david@octobus.net)
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.
"""core code for "sidedata" support

The "sidedata" are stored alongside the revision without actually being part of
its content and not affecting its hash. It's main use cases is to cache
important information related to a changesets.

The current implementation is experimental and subject to changes. Do not rely
on it in production.

Sidedata are stored in the revlog itself, withing the revision rawtext. They
are inserted, removed from it using the flagprocessors mechanism. The following
format is currently used::

    initial header:
        <number of sidedata; 2 bytes>
    sidedata (repeated N times):
        <sidedata-key; 2 bytes>
        <sidedata-entry-length: 4 bytes>
        <sidedata-content-sha1-digest: 20 bytes>
        <sidedata-content; X bytes>
    normal raw text:
        <all bytes remaining in the rawtext>

This is a simple and effective format. It should be enought to experiment with
the concept.
"""

from __future__ import absolute_import

import hashlib
import struct

from .. import error

SIDEDATA_HEADER = struct.Struct('>H')
SIDEDATA_ENTRY = struct.Struct('>HL20s')

def sidedatareadprocessor(rl, text):
    sidedata = {}
    offset = 0
    nbentry, = SIDEDATA_HEADER.unpack(text[:SIDEDATA_HEADER.size])
    offset += SIDEDATA_HEADER.size
    dataoffset = SIDEDATA_HEADER.size + (SIDEDATA_ENTRY.size * nbentry)
    for i in range(nbentry):
        nextoffset = offset + SIDEDATA_ENTRY.size
        key, size, storeddigest = SIDEDATA_ENTRY.unpack(text[offset:nextoffset])
        offset = nextoffset
        # read the data associated with that entry
        nextdataoffset = dataoffset + size
        entrytext = text[dataoffset:nextdataoffset]
        readdigest = hashlib.sha1(entrytext).digest()
        if storeddigest != readdigest:
            raise error.SidedataHashError(key, storeddigest, readdigest)
        sidedata[key] = entrytext
        dataoffset = nextdataoffset
    text = text[dataoffset:]
    return text, True, sidedata
