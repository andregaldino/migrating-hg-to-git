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

from .. import (
    error,
    util,
)

from . import (
    constants,
)

# Docket format
#
# * 4 bytes: revlog version
#          |   This is mandatory as docket must be compatible with the previous
#          |   revlog index header.
# * 8 bytes: size of index-data
# * 8 bytes: pending size of index-data
# * 8 bytes: size of data
# * 8 bytes: pending size of data
# * 1 bytes: default compression header
S_HEADER = struct.Struct(constants.INDEX_HEADER.format + 'LLLLc')


class RevlogDocket(object):
    """metadata associated with revlog"""

    def __init__(
        self,
        revlog,
        use_pending=False,
        version_header=None,
        index_end=0,
        pending_index_end=0,
        data_end=0,
        pending_data_end=0,
        default_compression_header=None,
    ):
        self._version_header = version_header
        self._read_only = bool(use_pending)
        self._dirty = False
        self._radix = revlog.radix
        self._path = revlog._docket_file
        self._opener = revlog.opener
        # thes asserts should be True as long as we have a single index filename
        assert index_end <= pending_index_end
        assert data_end <= pending_data_end
        self._initial_index_end = index_end
        self._pending_index_end = pending_index_end
        self._initial_data_end = data_end
        self._pending_data_end = pending_data_end
        if use_pending:
            self._index_end = self._pending_index_end
            self._data_end = self._pending_data_end
        else:
            self._index_end = self._initial_index_end
            self._data_end = self._initial_data_end
        self.default_compression_header = default_compression_header

    def index_filepath(self):
        """file path to the current index file associated to this docket"""
        # very simplistic version at first
        return b"%s.idx" % self._radix

    @property
    def index_end(self):
        return self._index_end

    @index_end.setter
    def index_end(self, new_size):
        if new_size != self._index_end:
            self._index_end = new_size
            self._dirty = True

    @property
    def data_end(self):
        return self._data_end

    @data_end.setter
    def data_end(self, new_size):
        if new_size != self._data_end:
            self._data_end = new_size
            self._dirty = True

    def write(self, transaction, pending=False, stripping=False):
        """write the modification of disk if any

        This make the new content visible to all process"""
        if not self._dirty:
            return False
        else:
            if self._read_only:
                msg = b'writing read-only docket: %s'
                msg %= self._path
                raise error.ProgrammingError(msg)
            if not stripping:
                # XXX we could, leverage the docket while stripping. However it
                # is not powerfull enough at the time of this comment
                transaction.addbackup(self._path, location=b'store')
            with self._opener(self._path, mode=b'w', atomictemp=True) as f:
                f.write(self._serialize(pending=pending))
            # if pending we still need to the write final data eventually
            self._dirty = pending
            return True

    def _serialize(self, pending=False):
        if pending:
            official_index_end = self._initial_index_end
            official_data_end = self._initial_data_end
        else:
            official_index_end = self._index_end
            official_data_end = self._data_end

        # this assert should be True as long as we have a single index filename
        assert official_data_end <= self._data_end
        data = (
            self._version_header,
            official_index_end,
            self._index_end,
            official_data_end,
            self._data_end,
            self.default_compression_header,
        )
        return S_HEADER.pack(*data)


def default_docket(revlog, version_header):
    """given a revlog version a new docket object for the given revlog"""
    rl_version = version_header & 0xFFFF
    if rl_version not in (constants.REVLOGV2, constants.CHANGELOGV2):
        return None
    comp = util.compengines[revlog._compengine].revlogheader()
    docket = RevlogDocket(
        revlog,
        version_header=version_header,
        default_compression_header=comp,
    )
    docket._dirty = True
    return docket


def parse_docket(revlog, data, use_pending=False):
    """given some docket data return a docket object for the given revlog"""
    header = S_HEADER.unpack(data[: S_HEADER.size])
    version_header = header[0]
    index_size = header[1]
    pending_index_size = header[2]
    data_size = header[3]
    pending_data_size = header[4]
    default_compression_header = header[5]
    docket = RevlogDocket(
        revlog,
        use_pending=use_pending,
        version_header=version_header,
        index_end=index_size,
        pending_index_end=pending_index_size,
        data_end=data_size,
        pending_data_end=pending_data_size,
        default_compression_header=default_compression_header,
    )
    return docket
