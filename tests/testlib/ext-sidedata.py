# ext-sidedata.py - small extension to test the sidedata logic
#
# Copyright 2019 Pierre-Yves David <pierre-yves.david@octobus.net)
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import hashlib
import struct

from mercurial import (
    extensions,
    node,
    revlog,
)

from mercurial.revlogutils import sidedata


def wrapaddrevision(
    orig, self, text, transaction, link, p1, p2, *args, **kwargs
):
    if kwargs.get('sidedata') is None:
        kwargs['sidedata'] = {}
    sd = kwargs['sidedata']
    ## let's store some arbitrary data just for testing
    # text length
    sd[sidedata.SD_TEST1] = struct.pack('>I', len(text))
    # and sha2 hashes
    sha256 = hashlib.sha256(text).digest()
    sd[sidedata.SD_TEST2] = struct.pack('>32s', sha256)
    return orig(self, text, transaction, link, p1, p2, *args, **kwargs)


def wraprevision(orig, self, nodeorrev, *args, **kwargs):
    text = orig(self, nodeorrev, *args, **kwargs)
    if nodeorrev != node.nullrev and nodeorrev != node.nullid:
        sd = self.sidedata(nodeorrev)
        if len(text) != struct.unpack('>I', sd[sidedata.SD_TEST1])[0]:
            raise RuntimeError('text size mismatch')
        expected = sd[sidedata.SD_TEST2]
        got = hashlib.sha256(text).digest()
        if got != expected:
            raise RuntimeError('sha256 mismatch')
    return text


def extsetup(ui):
    extensions.wrapfunction(revlog.revlog, 'addrevision', wrapaddrevision)
    extensions.wrapfunction(revlog.revlog, 'revision', wraprevision)
