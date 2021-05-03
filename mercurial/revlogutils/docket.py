# docket - code related to revlog "docket"
#
# Copyright 2021 Pierre-Yves David <pierre-yves.david@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

### Revlog docket file
#
# The revlog is stored on disk using multiple files:
#
# * a small docket file, containing metadata and a pointer,
#
# * an index file, containing fixed width information about revisions,
#
# * a data file, containing variable width data for these revisions,

from __future__ import absolute_import

import struct

from . import (
    constants,
)

# Docket format
#
# * 4 bytes: revlog version
#          |   This is mandatory as docket must be compatible with the previous
#          |   revlog index header.
S_HEADER = struct.Struct(constants.INDEX_HEADER.format)


class RevlogDocket(object):
    """metadata associated with revlog"""

    def __init__(self, revlog, version_header=None):
        self._version_header = version_header
        self._dirty = False
        self._radix = revlog.radix
        self._path = revlog._docket_file
        self._opener = revlog.opener

    def index_filepath(self):
        """file path to the current index file associated to this docket"""
        # very simplistic version at first
        return b"%s.idx" % self._radix

    def write(self, transaction):
        """write the modification of disk if any

        This make the new content visible to all process"""
        if self._dirty:
            transaction.addbackup(self._path, location=b'store')
            with self._opener(self._path, mode=b'w', atomictemp=True) as f:
                f.write(self._serialize())
            self._dirty = False

    def _serialize(self):
        return S_HEADER.pack(self._version_header)


def default_docket(revlog, version_header):
    """given a revlog version a new docket object for the given revlog"""
    if (version_header & 0xFFFF) != constants.REVLOGV2:
        return None
    docket = RevlogDocket(revlog, version_header=version_header)
    docket._dirty = True
    return docket


def parse_docket(revlog, data):
    """given some docket data return a docket object for the given revlog"""
    header = S_HEADER.unpack(data[: S_HEADER.size])
    (version_header,) = header
    docket = RevlogDocket(
        revlog,
        version_header=version_header,
    )
    return docket
