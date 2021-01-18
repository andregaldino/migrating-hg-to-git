# ext-sidedata.py - small extension to test the sidedata logic
#
# Copyright 2019 Pierre-Yves David <pierre-yves.david@octobus.net)
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import hashlib
import struct

from mercurial.node import (
    nullid,
    nullrev,
)
from mercurial import (
    extensions,
    requirements,
    revlog,
)

from mercurial.upgrade_utils import engine as upgrade_engine

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


def wrap_revisiondata(orig, self, nodeorrev, *args, **kwargs):
    text, sd = orig(self, nodeorrev, *args, **kwargs)
    if getattr(self, 'sidedatanocheck', False):
        return text, sd
    if self.version & 0xFFFF != 2:
        return text, sd
    if nodeorrev != nullrev and nodeorrev != nullid:
        if len(text) != struct.unpack('>I', sd[sidedata.SD_TEST1])[0]:
            raise RuntimeError('text size mismatch')
        expected = sd[sidedata.SD_TEST2]
        got = hashlib.sha256(text).digest()
        if got != expected:
            raise RuntimeError('sha256 mismatch')
    return text, sd


def wrapgetsidedatacompanion(orig, srcrepo, dstrepo):
    sidedatacompanion = orig(srcrepo, dstrepo)
    addedreqs = dstrepo.requirements - srcrepo.requirements
    if requirements.SIDEDATA_REQUIREMENT in addedreqs:
        assert sidedatacompanion is None  # deal with composition later

        def sidedatacompanion(revlog, rev):
            update = {}
            revlog.sidedatanocheck = True
            try:
                text = revlog.revision(rev)
            finally:
                del revlog.sidedatanocheck
            ## let's store some arbitrary data just for testing
            # text length
            update[sidedata.SD_TEST1] = struct.pack('>I', len(text))
            # and sha2 hashes
            sha256 = hashlib.sha256(text).digest()
            update[sidedata.SD_TEST2] = struct.pack('>32s', sha256)
            return False, (), update, 0, 0

    return sidedatacompanion


def extsetup(ui):
    extensions.wrapfunction(revlog.revlog, 'addrevision', wrapaddrevision)
    extensions.wrapfunction(revlog.revlog, '_revisiondata', wrap_revisiondata)
    extensions.wrapfunction(
        upgrade_engine, 'getsidedatacompanion', wrapgetsidedatacompanion
    )
