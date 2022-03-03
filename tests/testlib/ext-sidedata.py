# ext-sidedata.py - small extension to test the sidedata logic
#
# Copyright 2019 Pierre-Yves David <pierre-yves.david@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.


import hashlib
import struct

from mercurial.node import nullrev
from mercurial import (
    extensions,
    requirements,
    revlog,
)

from mercurial.upgrade_utils import engine as upgrade_engine

from mercurial.revlogutils import constants
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
    text = orig(self, nodeorrev, *args, **kwargs)
    sd = self.sidedata(nodeorrev)
    if getattr(self, 'sidedatanocheck', False):
        return text
    if self.hassidedata:
        return text
    if nodeorrev != nullrev and nodeorrev != self.nullid:
        cat1 = sd.get(sidedata.SD_TEST1)
        if cat1 is not None and len(text) != struct.unpack('>I', cat1)[0]:
            raise RuntimeError('text size mismatch')
        expected = sd.get(sidedata.SD_TEST2)
        got = hashlib.sha256(text).digest()
        if expected is not None and got != expected:
            raise RuntimeError('sha256 mismatch')
    return text


def wrapget_sidedata_helpers(orig, srcrepo, dstrepo):
    repo, computers, removers = orig(srcrepo, dstrepo)
    assert not computers and not removers  # deal with composition later
    addedreqs = dstrepo.requirements - srcrepo.requirements

    if requirements.REVLOGV2_REQUIREMENT in addedreqs:

        def computer(repo, revlog, rev, old_sidedata):
            assert not old_sidedata  # not supported yet
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
            return update, (0, 0)

        srcrepo.register_sidedata_computer(
            constants.KIND_CHANGELOG,
            b"whatever",
            (sidedata.SD_TEST1, sidedata.SD_TEST2),
            computer,
            0,
        )
        dstrepo.register_wanted_sidedata(b"whatever")

    return sidedata.get_sidedata_helpers(srcrepo, dstrepo._wanted_sidedata)


def extsetup(ui):
    extensions.wrapfunction(revlog.revlog, 'addrevision', wrapaddrevision)
    extensions.wrapfunction(revlog.revlog, '_revisiondata', wrap_revisiondata)
    extensions.wrapfunction(
        upgrade_engine, 'get_sidedata_helpers', wrapget_sidedata_helpers
    )


def reposetup(ui, repo):
    # We don't register sidedata computers because we don't care within these
    # tests
    repo.register_wanted_sidedata(sidedata.SD_TEST1)
    repo.register_wanted_sidedata(sidedata.SD_TEST2)
