# tiny extension to abort a transaction very late during test
#
# Copyright 2020 Pierre-Yves David <pierre-yves.david@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.


from mercurial import (
    error,
)


def abort(fp):
    raise error.Abort(b"This is a late abort")


def reposetup(ui, repo):
    class LateAbortRepo(repo.__class__):
        def transaction(self, *args, **kwargs):
            tr = super(LateAbortRepo, self).transaction(*args, **kwargs)
            tr.addfilegenerator(
                b'late-abort',
                [b'late-abort'],
                abort,
                order=9999999,
                post_finalize=True,
            )
            return tr

    repo.__class__ = LateAbortRepo
