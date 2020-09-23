# metadata.py -- code related to various metadata computation and access.
#
# Copyright 2019 Google, Inc <martinvonz@google.com>
# Copyright 2020 Pierre-Yves David <pierre-yves.david@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.
from __future__ import absolute_import, print_function

import multiprocessing

from . import (
    error,
    node,
    pycompat,
    util,
)

from .revlogutils import (
    flagutil as sidedataflag,
    sidedata as sidedatamod,
)


class ChangingFiles(object):
    """A class recording the changes made to a file by a changeset

    Actions performed on files are gathered into 3 sets:

    - added:   files actively added in the changeset.
    - removed: files removed in the revision
    - touched: files affected by the merge

    and copies information is held by 2 mappings

    - copied_from_p1: {"<new-name>": "<source-name-in-p1>"} mapping for copies
    - copied_from_p2: {"<new-name>": "<source-name-in-p2>"} mapping for copies

    See their inline help for details.
    """

    def __init__(
        self, touched=(), added=(), removed=(), p1_copies=(), p2_copies=(),
    ):
        self._added = set(added)
        self._removed = set(removed)
        self._touched = set(touched)
        self._touched.update(self._added)
        self._touched.update(self._removed)
        self._p1_copies = dict(p1_copies)
        self._p2_copies = dict(p2_copies)

    def __eq__(self, other):
        return (
            self.added == other.added
            and self.removed == other.removed
            and self.touched == other.touched
            and self.copied_from_p1 == other.copied_from_p1
            and self.copied_from_p2 == other.copied_from_p2
        )

    @property
    def added(self):
        """files actively added in the changeset

        Any file present in that revision that was absent in all the changeset's
        parents.

        In case of merge, this means a file absent in one of the parents but
        existing in the other will *not* be contained in this set. (They were
        added by an ancestor)
        """
        return frozenset(self._added)

    def mark_added(self, filename):
        self._added.add(filename)
        self._touched.add(filename)

    def update_added(self, filenames):
        for f in filenames:
            self.mark_added(f)

    @property
    def removed(self):
        """files actively removed by the changeset

        In case of merge this will only contain the set of files removing "new"
        content. For any file absent in the current changeset:

        a) If the file exists in both parents, it is clearly "actively" removed
        by this changeset.

        b) If a file exists in only one parent and in none of the common
        ancestors, then the file was newly added in one of the merged branches
        and then got "actively" removed.

        c) If a file exists in only one parent and at least one of the common
        ancestors using the same filenode, then the file was unchanged on one
        side and deleted on the other side. The merge "passively" propagated
        that deletion, but didn't "actively" remove the file. In this case the
        file is *not* included in the `removed` set.

        d) If a file exists in only one parent and at least one of the common
        ancestors using a different filenode, then the file was changed on one
        side and removed on the other side. The merge process "actively"
        decided to drop the new change and delete the file. Unlike in the
        previous case, (c), the file included in the `removed` set.

        Summary table for merge:

        case | exists in parents | exists in gca || removed
         (a) |       both        |     *         ||   yes
         (b) |       one         |     none      ||   yes
         (c) |       one         | same filenode ||   no
         (d) |       one         |  new filenode ||   yes
        """
        return frozenset(self._removed)

    def mark_removed(self, filename):
        self._removed.add(filename)
        self._touched.add(filename)

    def update_removed(self, filenames):
        for f in filenames:
            self.mark_removed(f)

    @property
    def touched(self):
        """files either actively modified, added or removed"""
        return frozenset(self._touched)

    def mark_touched(self, filename):
        self._touched.add(filename)

    def update_touched(self, filenames):
        for f in filenames:
            self.mark_touched(f)

    @property
    def copied_from_p1(self):
        return self._p1_copies.copy()

    def mark_copied_from_p1(self, source, dest):
        self._p1_copies[dest] = source

    def update_copies_from_p1(self, copies):
        for dest, source in copies.items():
            self.mark_copied_from_p1(source, dest)

    @property
    def copied_from_p2(self):
        return self._p2_copies.copy()

    def mark_copied_from_p2(self, source, dest):
        self._p2_copies[dest] = source

    def update_copies_from_p2(self, copies):
        for dest, source in copies.items():
            self.mark_copied_from_p2(source, dest)


def computechangesetfilesadded(ctx):
    """return the list of files added in a changeset
    """
    added = []
    for f in ctx.files():
        if not any(f in p for p in ctx.parents()):
            added.append(f)
    return added


def get_removal_filter(ctx, x=None):
    """return a function to detect files "wrongly" detected as `removed`

    When a file is removed relative to p1 in a merge, this
    function determines whether the absence is due to a
    deletion from a parent, or whether the merge commit
    itself deletes the file. We decide this by doing a
    simplified three way merge of the manifest entry for
    the file. There are two ways we decide the merge
    itself didn't delete a file:
    - neither parent (nor the merge) contain the file
    - exactly one parent contains the file, and that
      parent has the same filelog entry as the merge
      ancestor (or all of them if there two). In other
      words, that parent left the file unchanged while the
      other one deleted it.
    One way to think about this is that deleting a file is
    similar to emptying it, so the list of changed files
    should be similar either way. The computation
    described above is not done directly in _filecommit
    when creating the list of changed files, however
    it does something very similar by comparing filelog
    nodes.
    """

    if x is not None:
        p1, p2, m1, m2 = x
    else:
        p1 = ctx.p1()
        p2 = ctx.p2()
        m1 = p1.manifest()
        m2 = p2.manifest()

    @util.cachefunc
    def mas():
        p1n = p1.node()
        p2n = p2.node()
        cahs = ctx.repo().changelog.commonancestorsheads(p1n, p2n)
        if not cahs:
            cahs = [node.nullrev]
        return [ctx.repo()[r].manifest() for r in cahs]

    def deletionfromparent(f):
        if f in m1:
            return f not in m2 and all(
                f in ma and ma.find(f) == m1.find(f) for ma in mas()
            )
        elif f in m2:
            return all(f in ma and ma.find(f) == m2.find(f) for ma in mas())
        else:
            return True

    return deletionfromparent


def computechangesetfilesremoved(ctx):
    """return the list of files removed in a changeset
    """
    removed = []
    for f in ctx.files():
        if f not in ctx:
            removed.append(f)
    if removed:
        rf = get_removal_filter(ctx)
        removed = [r for r in removed if not rf(r)]
    return removed


def computechangesetcopies(ctx):
    """return the copies data for a changeset

    The copies data are returned as a pair of dictionnary (p1copies, p2copies).

    Each dictionnary are in the form: `{newname: oldname}`
    """
    p1copies = {}
    p2copies = {}
    p1 = ctx.p1()
    p2 = ctx.p2()
    narrowmatch = ctx._repo.narrowmatch()
    for dst in ctx.files():
        if not narrowmatch(dst) or dst not in ctx:
            continue
        copied = ctx[dst].renamed()
        if not copied:
            continue
        src, srcnode = copied
        if src in p1 and p1[src].filenode() == srcnode:
            p1copies[dst] = src
        elif src in p2 and p2[src].filenode() == srcnode:
            p2copies[dst] = src
    return p1copies, p2copies


def encodecopies(files, copies):
    items = []
    for i, dst in enumerate(files):
        if dst in copies:
            items.append(b'%d\0%s' % (i, copies[dst]))
    if len(items) != len(copies):
        raise error.ProgrammingError(
            b'some copy targets missing from file list'
        )
    return b"\n".join(items)


def decodecopies(files, data):
    try:
        copies = {}
        if not data:
            return copies
        for l in data.split(b'\n'):
            strindex, src = l.split(b'\0')
            i = int(strindex)
            dst = files[i]
            copies[dst] = src
        return copies
    except (ValueError, IndexError):
        # Perhaps someone had chosen the same key name (e.g. "p1copies") and
        # used different syntax for the value.
        return None


def encodefileindices(files, subset):
    subset = set(subset)
    indices = []
    for i, f in enumerate(files):
        if f in subset:
            indices.append(b'%d' % i)
    return b'\n'.join(indices)


def decodefileindices(files, data):
    try:
        subset = []
        if not data:
            return subset
        for strindex in data.split(b'\n'):
            i = int(strindex)
            if i < 0 or i >= len(files):
                return None
            subset.append(files[i])
        return subset
    except (ValueError, IndexError):
        # Perhaps someone had chosen the same key name (e.g. "added") and
        # used different syntax for the value.
        return None


def encode_files_sidedata(files):
    sortedfiles = sorted(files.touched)
    sidedata = {}
    p1copies = files.copied_from_p1
    if p1copies:
        p1copies = encodecopies(sortedfiles, p1copies)
        sidedata[sidedatamod.SD_P1COPIES] = p1copies
    p2copies = files.copied_from_p2
    if p2copies:
        p2copies = encodecopies(sortedfiles, p2copies)
        sidedata[sidedatamod.SD_P2COPIES] = p2copies
    filesadded = files.added
    if filesadded:
        filesadded = encodefileindices(sortedfiles, filesadded)
        sidedata[sidedatamod.SD_FILESADDED] = filesadded
    filesremoved = files.removed
    if filesremoved:
        filesremoved = encodefileindices(sortedfiles, filesremoved)
        sidedata[sidedatamod.SD_FILESREMOVED] = filesremoved
    if not sidedata:
        sidedata = None
    return sidedata


def decode_files_sidedata(changelogrevision, sidedata):
    """Return a ChangingFiles instance from a changelogrevision using sidata
    """
    touched = changelogrevision.files

    rawindices = sidedata.get(sidedatamod.SD_FILESADDED)
    added = decodefileindices(touched, rawindices)

    rawindices = sidedata.get(sidedatamod.SD_FILESREMOVED)
    removed = decodefileindices(touched, rawindices)

    rawcopies = sidedata.get(sidedatamod.SD_P1COPIES)
    p1_copies = decodecopies(touched, rawcopies)

    rawcopies = sidedata.get(sidedatamod.SD_P2COPIES)
    p2_copies = decodecopies(touched, rawcopies)

    return ChangingFiles(
        touched=touched,
        added=added,
        removed=removed,
        p1_copies=p1_copies,
        p2_copies=p2_copies,
    )


def _getsidedata(srcrepo, rev):
    ctx = srcrepo[rev]
    filescopies = computechangesetcopies(ctx)
    filesadded = computechangesetfilesadded(ctx)
    filesremoved = computechangesetfilesremoved(ctx)
    sidedata = {}
    if any([filescopies, filesadded, filesremoved]):
        sortedfiles = sorted(ctx.files())
        p1copies, p2copies = filescopies
        p1copies = encodecopies(sortedfiles, p1copies)
        p2copies = encodecopies(sortedfiles, p2copies)
        filesadded = encodefileindices(sortedfiles, filesadded)
        filesremoved = encodefileindices(sortedfiles, filesremoved)
        if p1copies:
            sidedata[sidedatamod.SD_P1COPIES] = p1copies
        if p2copies:
            sidedata[sidedatamod.SD_P2COPIES] = p2copies
        if filesadded:
            sidedata[sidedatamod.SD_FILESADDED] = filesadded
        if filesremoved:
            sidedata[sidedatamod.SD_FILESREMOVED] = filesremoved
    return sidedata


def getsidedataadder(srcrepo, destrepo):
    use_w = srcrepo.ui.configbool(b'experimental', b'worker.repository-upgrade')
    if pycompat.iswindows or not use_w:
        return _get_simple_sidedata_adder(srcrepo, destrepo)
    else:
        return _get_worker_sidedata_adder(srcrepo, destrepo)


def _sidedata_worker(srcrepo, revs_queue, sidedata_queue, tokens):
    """The function used by worker precomputing sidedata

    It read an input queue containing revision numbers
    It write in an output queue containing (rev, <sidedata-map>)

    The `None` input value is used as a stop signal.

    The `tokens` semaphore is user to avoid having too many unprocessed
    entries. The workers needs to acquire one token before fetching a task.
    They will be released by the consumer of the produced data.
    """
    tokens.acquire()
    rev = revs_queue.get()
    while rev is not None:
        data = _getsidedata(srcrepo, rev)
        sidedata_queue.put((rev, data))
        tokens.acquire()
        rev = revs_queue.get()
    # processing of `None` is completed, release the token.
    tokens.release()


BUFF_PER_WORKER = 50


def _get_worker_sidedata_adder(srcrepo, destrepo):
    """The parallel version of the sidedata computation

    This code spawn a pool of worker that precompute a buffer of sidedata
    before we actually need them"""
    # avoid circular import copies -> scmutil -> worker -> copies
    from . import worker

    nbworkers = worker._numworkers(srcrepo.ui)

    tokens = multiprocessing.BoundedSemaphore(nbworkers * BUFF_PER_WORKER)
    revsq = multiprocessing.Queue()
    sidedataq = multiprocessing.Queue()

    assert srcrepo.filtername is None
    # queue all tasks beforehand, revision numbers are small and it make
    # synchronisation simpler
    #
    # Since the computation for each node can be quite expensive, the overhead
    # of using a single queue is not revelant. In practice, most computation
    # are fast but some are very expensive and dominate all the other smaller
    # cost.
    for r in srcrepo.changelog.revs():
        revsq.put(r)
    # queue the "no more tasks" markers
    for i in range(nbworkers):
        revsq.put(None)

    allworkers = []
    for i in range(nbworkers):
        args = (srcrepo, revsq, sidedataq, tokens)
        w = multiprocessing.Process(target=_sidedata_worker, args=args)
        allworkers.append(w)
        w.start()

    # dictionnary to store results for revision higher than we one we are
    # looking for. For example, if we need the sidedatamap for 42, and 43 is
    # received, when shelve 43 for later use.
    staging = {}

    def sidedata_companion(revlog, rev):
        sidedata = {}
        if util.safehasattr(revlog, b'filteredrevs'):  # this is a changelog
            # Is the data previously shelved ?
            sidedata = staging.pop(rev, None)
            if sidedata is None:
                # look at the queued result until we find the one we are lookig
                # for (shelve the other ones)
                r, sidedata = sidedataq.get()
                while r != rev:
                    staging[r] = sidedata
                    r, sidedata = sidedataq.get()
            tokens.release()
        return False, (), sidedata

    return sidedata_companion


def _get_simple_sidedata_adder(srcrepo, destrepo):
    """The simple version of the sidedata computation

    It just compute it in the same thread on request"""

    def sidedatacompanion(revlog, rev):
        sidedata = {}
        if util.safehasattr(revlog, 'filteredrevs'):  # this is a changelog
            sidedata = _getsidedata(srcrepo, rev)
        return False, (), sidedata

    return sidedatacompanion


def getsidedataremover(srcrepo, destrepo):
    def sidedatacompanion(revlog, rev):
        f = ()
        if util.safehasattr(revlog, 'filteredrevs'):  # this is a changelog
            if revlog.flags(rev) & sidedataflag.REVIDX_SIDEDATA:
                f = (
                    sidedatamod.SD_P1COPIES,
                    sidedatamod.SD_P2COPIES,
                    sidedatamod.SD_FILESADDED,
                    sidedatamod.SD_FILESREMOVED,
                )
        return False, f, {}

    return sidedatacompanion
