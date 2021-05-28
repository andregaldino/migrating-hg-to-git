# censor code related to censoring revision
#
# Copyright 2021 Pierre-Yves David <pierre-yves.david@octobus.net>
# Copyright 2015 Google, Inc <martinvonz@google.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from ..node import (
    nullrev,
)
from ..i18n import _
from .. import (
    error,
)
from ..utils import (
    storageutil,
)
from . import constants


def v1_censor(rl, tr, censornode, tombstone=b''):
    """censors a revision in a "version 1" revlog"""
    assert rl._format_version == constants.REVLOGV1, rl._format_version

    # avoid cycle
    from .. import revlog

    censorrev = rl.rev(censornode)
    tombstone = storageutil.packmeta({b'censored': tombstone}, b'')

    if len(tombstone) > rl.rawsize(censorrev):
        raise error.Abort(
            _(b'censor tombstone must be no longer than censored data')
        )

    # Rewriting the revlog in place is hard. Our strategy for censoring is
    # to create a new revlog, copy all revisions to it, then replace the
    # revlogs on transaction close.
    #
    # This is a bit dangerous. We could easily have a mismatch of state.
    newrl = revlog.revlog(
        rl.opener,
        target=rl.target,
        radix=rl.radix,
        postfix=b'tmpcensored',
        censorable=True,
    )
    newrl._format_version = rl._format_version
    newrl._format_flags = rl._format_flags
    newrl._generaldelta = rl._generaldelta
    newrl._parse_index = rl._parse_index

    for rev in rl.revs():
        node = rl.node(rev)
        p1, p2 = rl.parents(node)

        if rev == censorrev:
            newrl.addrawrevision(
                tombstone,
                tr,
                rl.linkrev(censorrev),
                p1,
                p2,
                censornode,
                constants.REVIDX_ISCENSORED,
            )

            if newrl.deltaparent(rev) != nullrev:
                m = _(b'censored revision stored as delta; cannot censor')
                h = _(
                    b'censoring of revlogs is not fully implemented;'
                    b' please report this bug'
                )
                raise error.Abort(m, hint=h)
            continue

        if rl.iscensored(rev):
            if rl.deltaparent(rev) != nullrev:
                m = _(
                    b'cannot censor due to censored '
                    b'revision having delta stored'
                )
                raise error.Abort(m)
            rawtext = rl._chunk(rev)
        else:
            rawtext = rl.rawdata(rev)

        newrl.addrawrevision(
            rawtext, tr, rl.linkrev(rev), p1, p2, node, rl.flags(rev)
        )

    tr.addbackup(rl._indexfile, location=b'store')
    if not rl._inline:
        tr.addbackup(rl._datafile, location=b'store')

    rl.opener.rename(newrl._indexfile, rl._indexfile)
    if not rl._inline:
        rl.opener.rename(newrl._datafile, rl._datafile)

    rl.clearcaches()
    rl._loadindex()
