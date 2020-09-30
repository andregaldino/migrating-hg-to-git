# metadata.py -- code related to various metadata computation and access.
#
# Copyright 2019 Google, Inc <martinvonz@google.com>
# Copyright 2020 Pierre-Yves David <pierre-yves.david@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.
from __future__ import absolute_import, print_function

import multiprocessing
import struct

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
    """A class recording the changes made to files by a changeset

    Actions performed on files are gathered into 3 sets:

    - added:   files actively added in the changeset.
    - merged:  files whose history got merged
    - removed: files removed in the revision
    - salvaged: files that might have been deleted by a merge but were not
    - touched: files affected by the merge

    and copies information is held by 2 mappings

    - copied_from_p1: {"<new-name>": "<source-name-in-p1>"} mapping for copies
    - copied_from_p2: {"<new-name>": "<source-name-in-p2>"} mapping for copies

    See their inline help for details.
    """

    def __init__(
        self,
        touched=None,
        added=None,
        removed=None,
        merged=None,
        salvaged=None,
        p1_copies=None,
        p2_copies=None,
    ):
        self._added = set(() if added is None else added)
        self._merged = set(() if merged is None else merged)
        self._removed = set(() if removed is None else removed)
        self._touched = set(() if touched is None else touched)
        self._salvaged = set(() if salvaged is None else salvaged)
        self._touched.update(self._added)
        self._touched.update(self._merged)
        self._touched.update(self._removed)
        self._p1_copies = dict(() if p1_copies is None else p1_copies)
        self._p2_copies = dict(() if p2_copies is None else p2_copies)

    def __eq__(self, other):
        return (
            self.added == other.added
            and self.merged == other.merged
            and self.removed == other.removed
            and self.salvaged == other.salvaged
            and self.touched == other.touched
            and self.copied_from_p1 == other.copied_from_p1
            and self.copied_from_p2 == other.copied_from_p2
        )

    @util.propertycache
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
        if 'added' in vars(self):
            del self.added
        self._added.add(filename)
        self.mark_touched(filename)

    def update_added(self, filenames):
        for f in filenames:
            self.mark_added(f)

    @util.propertycache
    def merged(self):
        """files actively merged during a merge

        Any modified files which had modification on both size that needed merging.

        In this case a new filenode was created and it has two parents.
        """
        return frozenset(self._merged)

    def mark_merged(self, filename):
        if 'merged' in vars(self):
            del self.merged
        self._merged.add(filename)
        self.mark_touched(filename)

    def update_merged(self, filenames):
        for f in filenames:
            self.mark_merged(f)

    @util.propertycache
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
        if 'removed' in vars(self):
            del self.removed
        self._removed.add(filename)
        self.mark_touched(filename)

    def update_removed(self, filenames):
        for f in filenames:
            self.mark_removed(f)

    @util.propertycache
    def salvaged(self):
        """files that might have been deleted by a merge, but still exists.

        During a merge, the manifest merging might select some files for
        removal, or for a removed/changed conflict. If at commit time the file
        still exists, its removal was "reverted" and the file is "salvaged"
        """
        return frozenset(self._salvaged)

    def mark_salvaged(self, filename):
        if "salvaged" in vars(self):
            del self.salvaged
        self._salvaged.add(filename)
        self.mark_touched(filename)

    def update_salvaged(self, filenames):
        for f in filenames:
            self.mark_salvaged(f)

    @util.propertycache
    def touched(self):
        """files either actively modified, added or removed"""
        return frozenset(self._touched)

    def mark_touched(self, filename):
        if 'touched' in vars(self):
            del self.touched
        self._touched.add(filename)

    def update_touched(self, filenames):
        for f in filenames:
            self.mark_touched(f)

    @util.propertycache
    def copied_from_p1(self):
        return self._p1_copies.copy()

    def mark_copied_from_p1(self, source, dest):
        if 'copied_from_p1' in vars(self):
            del self.copied_from_p1
        self._p1_copies[dest] = source

    def update_copies_from_p1(self, copies):
        for dest, source in copies.items():
            self.mark_copied_from_p1(source, dest)

    @util.propertycache
    def copied_from_p2(self):
        return self._p2_copies.copy()

    def mark_copied_from_p2(self, source, dest):
        if 'copied_from_p2' in vars(self):
            del self.copied_from_p2
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


def computechangesetfilesmerged(ctx):
    """return the list of files merged in a changeset
    """
    merged = []
    if len(ctx.parents()) < 2:
        return merged
    for f in ctx.files():
        if f in ctx:
            fctx = ctx[f]
            parents = fctx._filelog.parents(fctx._filenode)
            if parents[1] != node.nullid:
                merged.append(f)
    return merged


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


# see mercurial/helptext/internals/revlogs.txt for details about the format

ACTION_MASK = int("111" "00", 2)
# note: untouched file used as copy source will as `000` for this mask.
ADDED_FLAG = int("001" "00", 2)
MERGED_FLAG = int("010" "00", 2)
REMOVED_FLAG = int("011" "00", 2)
# `100` is reserved for future use
TOUCHED_FLAG = int("101" "00", 2)

COPIED_MASK = int("11", 2)
COPIED_FROM_P1_FLAG = int("10", 2)
COPIED_FROM_P2_FLAG = int("11", 2)

# structure is <flag><filename-end><copy-source>
INDEX_HEADER = struct.Struct(">L")
INDEX_ENTRY = struct.Struct(">bLL")


def encode_files_sidedata(files):
    all_files = set(files.touched - files.salvaged)
    all_files.update(files.copied_from_p1.values())
    all_files.update(files.copied_from_p2.values())
    all_files = sorted(all_files)
    file_idx = {f: i for (i, f) in enumerate(all_files)}
    file_idx[None] = 0

    chunks = [INDEX_HEADER.pack(len(all_files))]

    filename_length = 0
    for f in all_files:
        filename_size = len(f)
        filename_length += filename_size
        flag = 0
        if f in files.added:
            flag |= ADDED_FLAG
        elif f in files.merged:
            flag |= MERGED_FLAG
        elif f in files.removed:
            flag |= REMOVED_FLAG
        elif f in files.touched:
            flag |= TOUCHED_FLAG

        copy = None
        if f in files.copied_from_p1:
            flag |= COPIED_FROM_P1_FLAG
            copy = files.copied_from_p1.get(f)
        elif f in files.copied_from_p2:
            copy = files.copied_from_p2.get(f)
            flag |= COPIED_FROM_P2_FLAG
        copy_idx = file_idx[copy]
        chunks.append(INDEX_ENTRY.pack(flag, filename_length, copy_idx))
    chunks.extend(all_files)
    return {sidedatamod.SD_FILES: b''.join(chunks)}


def decode_files_sidedata(sidedata):
    md = ChangingFiles()
    raw = sidedata.get(sidedatamod.SD_FILES)

    if raw is None:
        return md

    copies = []
    all_files = []

    assert len(raw) >= INDEX_HEADER.size
    total_files = INDEX_HEADER.unpack_from(raw, 0)[0]

    offset = INDEX_HEADER.size
    file_offset_base = offset + (INDEX_ENTRY.size * total_files)
    file_offset_last = file_offset_base

    assert len(raw) >= file_offset_base

    for idx in range(total_files):
        flag, file_end, copy_idx = INDEX_ENTRY.unpack_from(raw, offset)
        file_end += file_offset_base
        filename = raw[file_offset_last:file_end]
        filesize = file_end - file_offset_last
        assert len(filename) == filesize
        offset += INDEX_ENTRY.size
        file_offset_last = file_end
        all_files.append(filename)
        if flag & ACTION_MASK == ADDED_FLAG:
            md.mark_added(filename)
        elif flag & ACTION_MASK == MERGED_FLAG:
            md.mark_merged(filename)
        elif flag & ACTION_MASK == REMOVED_FLAG:
            md.mark_removed(filename)
        elif flag & ACTION_MASK == TOUCHED_FLAG:
            md.mark_touched(filename)

        copied = None
        if flag & COPIED_MASK == COPIED_FROM_P1_FLAG:
            copied = md.mark_copied_from_p1
        elif flag & COPIED_MASK == COPIED_FROM_P2_FLAG:
            copied = md.mark_copied_from_p2

        if copied is not None:
            copies.append((copied, filename, copy_idx))

    for copied, filename, copy_idx in copies:
        copied(all_files[copy_idx], filename)

    return md


def _getsidedata(srcrepo, rev):
    ctx = srcrepo[rev]
    filescopies = computechangesetcopies(ctx)
    filesadded = computechangesetfilesadded(ctx)
    filesremoved = computechangesetfilesremoved(ctx)
    filesmerged = computechangesetfilesmerged(ctx)
    files = ChangingFiles()
    files.update_touched(ctx.files())
    files.update_added(filesadded)
    files.update_removed(filesremoved)
    files.update_merged(filesmerged)
    files.update_copies_from_p1(filescopies[0])
    files.update_copies_from_p2(filescopies[1])
    return encode_files_sidedata(files)


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
