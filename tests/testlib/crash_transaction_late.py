# tiny extension to abort a transaction very late during test
#
# Copyright 2020 Pierre-Yves David <pierre-yves.david@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

from mercurial import (
    error,
    transaction,
)


def abort(fp):
    raise error.Abort(b"This is a late abort")


def reposetup(ui, repo):

    transaction.postfinalizegenerators.add(b'late-abort')

    class LateAbortRepo(repo.__class__):
        def transaction(self, *args, **kwargs):
            tr = super(LateAbortRepo, self).transaction(*args, **kwargs)
            tr.addfilegenerator(
                b'late-abort', [b'late-abort'], abort, order=9999999
            )
            return tr

    repo.__class__ = LateAbortRepo
