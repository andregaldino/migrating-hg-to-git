# mercurial.revlogutils -- basic utilities for revlog
#
# Copyright 2019 Pierre-Yves David <pierre-yves.david@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

from ..interfaces import repository


def offset_type(offset, type):
    if (type & ~repository.REVISION_FLAGS_KNOWN) != 0:
        raise ValueError(b'unknown revlog index flags: %d' % type)
    return int(int(offset) << 16 | type)
