# coding: utf8
# ext-sidedata-5.py - small extension to test (differently still) the sidedata
# logic
#
# Simulates a server for a simple sidedata exchange.
#
# Copyright 2021 Raphaël Gomès <rgomes@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.


import hashlib
import struct

from mercurial import (
    extensions,
    revlog,
)


from mercurial.revlogutils import sidedata as sidedatamod
from mercurial.revlogutils import constants

NO_FLAGS = (0, 0)


def compute_sidedata_1(repo, revlog, rev, sidedata, text=None):
    sidedata = sidedata.copy()
    if text is None:
        text = revlog.revision(rev)
    sidedata[sidedatamod.SD_TEST1] = struct.pack('>I', len(text))
    return sidedata, NO_FLAGS


def compute_sidedata_2(repo, revlog, rev, sidedata, text=None):
    sidedata = sidedata.copy()
    if text is None:
        text = revlog.revision(rev)
    sha256 = hashlib.sha256(text).digest()
    sidedata[sidedatamod.SD_TEST2] = struct.pack('>32s', sha256)
    return sidedata, NO_FLAGS


def reposetup(ui, repo):
    # Sidedata keys happen to be the same as the categories, easier for testing.
    for kind in constants.ALL_KINDS:
        repo.register_sidedata_computer(
            kind,
            sidedatamod.SD_TEST1,
            (sidedatamod.SD_TEST1,),
            compute_sidedata_1,
            0,
        )
        repo.register_sidedata_computer(
            kind,
            sidedatamod.SD_TEST2,
            (sidedatamod.SD_TEST2,),
            compute_sidedata_2,
            0,
        )

    # We don't register sidedata computers because we don't care within these
    # tests
    repo.register_wanted_sidedata(sidedatamod.SD_TEST1)
    repo.register_wanted_sidedata(sidedatamod.SD_TEST2)


def wrapaddrevision(
    orig, self, text, transaction, link, p1, p2, *args, **kwargs
):
    if kwargs.get('sidedata') is None:
        kwargs['sidedata'] = {}
    sd = kwargs['sidedata']
    ## let's store some arbitrary data just for testing
    # text length
    sd[sidedatamod.SD_TEST1] = struct.pack('>I', len(text))
    # and sha2 hashes
    sha256 = hashlib.sha256(text).digest()
    sd[sidedatamod.SD_TEST2] = struct.pack('>32s', sha256)
    return orig(self, text, transaction, link, p1, p2, *args, **kwargs)


def extsetup(ui):
    extensions.wrapfunction(revlog.revlog, 'addrevision', wrapaddrevision)
