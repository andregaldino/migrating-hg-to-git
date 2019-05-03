# copies.py - copy detection for Mercurial
#
# Copyright 2008 Matt Mackall <mpm@selenic.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import collections
import heapq
import os

from .i18n import _

from . import (
    match as matchmod,
    node,
    pathutil,
    util,
)
from .utils import (
    stringutil,
)

def _findlimit(repo, ctxa, ctxb):
    """
    Find the last revision that needs to be checked to ensure that a full
    transitive closure for file copies can be properly calculated.
    Generally, this means finding the earliest revision number that's an
    ancestor of a or b but not both, except when a or b is a direct descendent
    of the other, in which case we can return the minimum revnum of a and b.
    """

    # basic idea:
    # - mark a and b with different sides
    # - if a parent's children are all on the same side, the parent is
    #   on that side, otherwise it is on no side
    # - walk the graph in topological order with the help of a heap;
    #   - add unseen parents to side map
    #   - clear side of any parent that has children on different sides
    #   - track number of interesting revs that might still be on a side
    #   - track the lowest interesting rev seen
    #   - quit when interesting revs is zero

    cl = repo.changelog
    wdirparents = None
    a = ctxa.rev()
    b = ctxb.rev()
    if a is None:
        wdirparents = (ctxa.p1(), ctxa.p2())
        a = node.wdirrev
    if b is None:
        assert not wdirparents
        wdirparents = (ctxb.p1(), ctxb.p2())
        b = node.wdirrev

    side = {a: -1, b: 1}
    visit = [-a, -b]
    heapq.heapify(visit)
    interesting = len(visit)
    limit = node.wdirrev

    while interesting:
        r = -heapq.heappop(visit)
        if r == node.wdirrev:
            parents = [pctx.rev() for pctx in wdirparents]
        else:
            parents = cl.parentrevs(r)
        if parents[1] == node.nullrev:
            parents = parents[:1]
        for p in parents:
            if p not in side:
                # first time we see p; add it to visit
                side[p] = side[r]
                if side[p]:
                    interesting += 1
                heapq.heappush(visit, -p)
            elif side[p] and side[p] != side[r]:
                # p was interesting but now we know better
                side[p] = 0
                interesting -= 1
        if side[r]:
            limit = r # lowest rev visited
            interesting -= 1

    # Consider the following flow (see test-commit-amend.t under issue4405):
    # 1/ File 'a0' committed
    # 2/ File renamed from 'a0' to 'a1' in a new commit (call it 'a1')
    # 3/ Move back to first commit
    # 4/ Create a new commit via revert to contents of 'a1' (call it 'a1-amend')
    # 5/ Rename file from 'a1' to 'a2' and commit --amend 'a1-msg'
    #
    # During the amend in step five, we will be in this state:
    #
    # @  3 temporary amend commit for a1-amend
    # |
    # o  2 a1-amend
    # |
    # | o  1 a1
    # |/
    # o  0 a0
    #
    # When _findlimit is called, a and b are revs 3 and 0, so limit will be 2,
    # yet the filelog has the copy information in rev 1 and we will not look
    # back far enough unless we also look at the a and b as candidates.
    # This only occurs when a is a descendent of b or visa-versa.
    return min(limit, a, b)

def _chainandfilter(src, dst, a, b):
    """chain two sets of copies 'a' and 'b' and filter result"""

    # When chaining copies in 'a' (from 'src' via some other commit 'mid') with
    # copies in 'b' (from 'mid' to 'dst'), we can get the different cases in the
    # following table (not including trivial cases). For example, case 2 is
    # where a file existed in 'src' and remained under that name in 'mid' and
    # then was renamed between 'mid' and 'dst'.
    #
    # case src mid dst result
    #   1   x   y   -    -
    #   2   x   y   y   x->y
    #   3   x   y   x    -
    #   4   x   y   z   x->z
    #   5   -   x   y    -
    #   6   x   x   y   x->y
    #
    # _chain() takes care of chaining the copies in 'a' and 'b', but it
    # cannot tell the difference between cases 1 and 2, between 3 and 4, or
    # between 5 and 6, so it includes all cases in its result.
    # Cases 1, 3, and 5 are then removed by _filter().

    t = _chain(a, b)
    _filter(src, dst, t)
    return t

def _filter(src, dst, t):
    """filters out invalid copies after chaining"""
    for k, v in list(t.items()):
        # remove copies from files that didn't exist
        if v not in src:
            del t[k]
        # remove criss-crossed copies
        elif k in src and v in dst:
            del t[k]
        # remove copies to files that were then removed
        elif k not in dst:
            del t[k]

def _chain(a, b):
    """chain two sets of copies 'a' and 'b'"""
    t = a.copy()
    for k, v in b.iteritems():
        if v in t:
            t[k] = t[v]
        else:
            t[k] = v
    return t

def _tracefile(fctx, am, limit):
    """return file context that is the ancestor of fctx present in ancestor
    manifest am, stopping after the first ancestor lower than limit"""

    for f in fctx.ancestors():
        if am.get(f.path(), None) == f.filenode():
            return f
        if not f.isintroducedafter(limit):
            return None

def _dirstatecopies(repo, match=None):
    ds = repo.dirstate
    c = ds.copies().copy()
    for k in list(c):
        if ds[k] not in 'anm' or (match and not match(k)):
            del c[k]
    return c

def _computeforwardmissing(a, b, match=None):
    """Computes which files are in b but not a.
    This is its own function so extensions can easily wrap this call to see what
    files _forwardcopies is about to process.
    """
    ma = a.manifest()
    mb = b.manifest()
    return mb.filesnotin(ma, match=match)

def usechangesetcentricalgo(repo):
    """Checks if we should use changeset-centric copy algorithms"""
    return (repo.ui.config('experimental', 'copies.read-from') in
            ('changeset-only', 'compatibility'))

def _committedforwardcopies(a, b, match):
    """Like _forwardcopies(), but b.rev() cannot be None (working copy)"""
    # files might have to be traced back to the fctx parent of the last
    # one-side-only changeset, but not further back than that
    repo = a._repo

    if usechangesetcentricalgo(repo):
        return _changesetforwardcopies(a, b, match)

    debug = repo.ui.debugflag and repo.ui.configbool('devel', 'debug.copies')
    dbg = repo.ui.debug
    if debug:
        dbg('debug.copies:    looking into rename from %s to %s\n'
            % (a, b))
    limit = _findlimit(repo, a, b)
    if debug:
        dbg('debug.copies:      search limit: %d\n' % limit)
    am = a.manifest()

    # find where new files came from
    # we currently don't try to find where old files went, too expensive
    # this means we can miss a case like 'hg rm b; hg cp a b'
    cm = {}

    # Computing the forward missing is quite expensive on large manifests, since
    # it compares the entire manifests. We can optimize it in the common use
    # case of computing what copies are in a commit versus its parent (like
    # during a rebase or histedit). Note, we exclude merge commits from this
    # optimization, since the ctx.files() for a merge commit is not correct for
    # this comparison.
    forwardmissingmatch = match
    if b.p1() == a and b.p2().node() == node.nullid:
        filesmatcher = matchmod.exact(b.files())
        forwardmissingmatch = matchmod.intersectmatchers(match, filesmatcher)
    missing = _computeforwardmissing(a, b, match=forwardmissingmatch)

    ancestrycontext = a._repo.changelog.ancestors([b.rev()], inclusive=True)

    if debug:
        dbg('debug.copies:      missing files to search: %d\n' % len(missing))

    for f in sorted(missing):
        if debug:
            dbg('debug.copies:        tracing file: %s\n' % f)
        fctx = b[f]
        fctx._ancestrycontext = ancestrycontext

        if debug:
            start = util.timer()
        ofctx = _tracefile(fctx, am, limit)
        if ofctx:
            if debug:
                dbg('debug.copies:          rename of: %s\n' % ofctx._path)
            cm[f] = ofctx.path()
        if debug:
            dbg('debug.copies:          time: %f seconds\n'
                % (util.timer() - start))
    return cm

def _changesetforwardcopies(a, b, match):
    if a.rev() == node.nullrev:
        return {}

    repo = a.repo()
    children = {}
    cl = repo.changelog
    missingrevs = cl.findmissingrevs(common=[a.rev()], heads=[b.rev()])
    for r in missingrevs:
        for p in cl.parentrevs(r):
            if p == node.nullrev:
                continue
            if p not in children:
                children[p] = [r]
            else:
                children[p].append(r)

    roots = set(children) - set(missingrevs)
    # 'work' contains 3-tuples of a (revision number, parent number, copies).
    # The parent number is only used for knowing which parent the copies dict
    # came from.
    work = [(r, 1, {}) for r in roots]
    heapq.heapify(work)
    alwaysmatch = match.always()
    while work:
        r, i1, copies1 = heapq.heappop(work)
        if work and work[0][0] == r:
            # We are tracing copies from both parents
            r, i2, copies2 = heapq.heappop(work)
            copies = {}
            allcopies = set(copies1) | set(copies2)
            # TODO: perhaps this filtering should be done as long as ctx
            # is merge, whether or not we're tracing from both parent.
            for dst in allcopies:
                if not alwaysmatch and not match(dst):
                    continue
                # Unlike when copies are stored in the filelog, we consider
                # it a copy even if the destination already existed on the
                # other branch. It's simply too expensive to check if the
                # file existed in the manifest.
                if dst in copies1:
                    # If it was copied on the p1 side, mark it as copied from
                    # that side, even if it was also copied on the p2 side.
                    copies[dst] = copies1[dst]
                else:
                    copies[dst] = copies2[dst]
        else:
            copies = copies1
        if r == b.rev():
            _filter(a, b, copies)
            return copies
        for i, c in enumerate(children[r]):
            childctx = repo[c]
            if r == childctx.p1().rev():
                parent = 1
                childcopies = childctx.p1copies()
            else:
                assert r == childctx.p2().rev()
                parent = 2
                childcopies = childctx.p2copies()
            if not alwaysmatch:
                childcopies = {dst: src for dst, src in childcopies.items()
                               if match(dst)}
            # Copy the dict only if later iterations will also need it
            if i != len(children[r]) - 1:
                copies = copies.copy()
            if childcopies:
                childcopies = _chain(copies, childcopies)
            else:
                childcopies = copies
            for f in childctx.filesremoved():
                if f in childcopies:
                    del childcopies[f]
            heapq.heappush(work, (c, parent, childcopies))
    assert False

def _forwardcopies(a, b, match=None):
    """find {dst@b: src@a} copy mapping where a is an ancestor of b"""

    match = a.repo().narrowmatch(match)
    # check for working copy
    if b.rev() is None:
        if a == b.p1():
            # short-circuit to avoid issues with merge states
            return _dirstatecopies(b._repo, match)

        cm = _committedforwardcopies(a, b.p1(), match)
        # combine copies from dirstate if necessary
        return _chainandfilter(a, b, cm, _dirstatecopies(b._repo, match))
    return _committedforwardcopies(a, b, match)

def _backwardrenames(a, b, match):
    if a._repo.ui.config('experimental', 'copytrace') == 'off':
        return {}

    # Even though we're not taking copies into account, 1:n rename situations
    # can still exist (e.g. hg cp a b; hg mv a c). In those cases we
    # arbitrarily pick one of the renames.
    # We don't want to pass in "match" here, since that would filter
    # the destination by it. Since we're reversing the copies, we want
    # to filter the source instead.
    f = _forwardcopies(b, a)
    r = {}
    for k, v in sorted(f.iteritems()):
        if match and not match(v):
            continue
        # remove copies
        if v in a:
            continue
        r[v] = k
    return r

def pathcopies(x, y, match=None):
    """find {dst@y: src@x} copy mapping for directed compare"""
    repo = x._repo
    debug = repo.ui.debugflag and repo.ui.configbool('devel', 'debug.copies')
    if debug:
        repo.ui.debug('debug.copies: searching copies from %s to %s\n'
                      % (x, y))
    if x == y or not x or not y:
        return {}
    a = y.ancestor(x)
    if a == x:
        if debug:
            repo.ui.debug('debug.copies: search mode: forward\n')
        return _forwardcopies(x, y, match=match)
    if a == y:
        if debug:
            repo.ui.debug('debug.copies: search mode: backward\n')
        return _backwardrenames(x, y, match=match)
    if debug:
        repo.ui.debug('debug.copies: search mode: combined\n')
    return _chainandfilter(x, y, _backwardrenames(x, a, match=match),
                           _forwardcopies(a, y, match=match))

def mergecopies(repo, c1, c2, base):
    """
    Finds moves and copies between context c1 and c2 that are relevant for
    merging. 'base' will be used as the merge base.

    Copytracing is used in commands like rebase, merge, unshelve, etc to merge
    files that were moved/ copied in one merge parent and modified in another.
    For example:

    o          ---> 4 another commit
    |
    |   o      ---> 3 commit that modifies a.txt
    |  /
    o /        ---> 2 commit that moves a.txt to b.txt
    |/
    o          ---> 1 merge base

    If we try to rebase revision 3 on revision 4, since there is no a.txt in
    revision 4, and if user have copytrace disabled, we prints the following
    message:

    ```other changed <file> which local deleted```

    Returns five dicts: "copy", "movewithdir", "diverge", "renamedelete" and
    "dirmove".

    "copy" is a mapping from destination name -> source name,
    where source is in c1 and destination is in c2 or vice-versa.

    "movewithdir" is a mapping from source name -> destination name,
    where the file at source present in one context but not the other
    needs to be moved to destination by the merge process, because the
    other context moved the directory it is in.

    "diverge" is a mapping of source name -> list of destination names
    for divergent renames.

    "renamedelete" is a mapping of source name -> list of destination
    names for files deleted in c1 that were renamed in c2 or vice-versa.

    "dirmove" is a mapping of detected source dir -> destination dir renames.
    This is needed for handling changes to new files previously grafted into
    renamed directories.

    This function calls different copytracing algorithms based on config.
    """
    # avoid silly behavior for update from empty dir
    if not c1 or not c2 or c1 == c2:
        return {}, {}, {}, {}, {}

    narrowmatch = c1.repo().narrowmatch()

    # avoid silly behavior for parent -> working dir
    if c2.node() is None and c1.node() == repo.dirstate.p1():
        return _dirstatecopies(repo, narrowmatch), {}, {}, {}, {}

    copytracing = repo.ui.config('experimental', 'copytrace')
    if stringutil.parsebool(copytracing) is False:
        # stringutil.parsebool() returns None when it is unable to parse the
        # value, so we should rely on making sure copytracing is on such cases
        return {}, {}, {}, {}, {}

    if usechangesetcentricalgo(repo):
        # The heuristics don't make sense when we need changeset-centric algos
        return _fullcopytracing(repo, c1, c2, base)

    # Copy trace disabling is explicitly below the node == p1 logic above
    # because the logic above is required for a simple copy to be kept across a
    # rebase.
    if copytracing == 'heuristics':
        # Do full copytracing if only non-public revisions are involved as
        # that will be fast enough and will also cover the copies which could
        # be missed by heuristics
        if _isfullcopytraceable(repo, c1, base):
            return _fullcopytracing(repo, c1, c2, base)
        return _heuristicscopytracing(repo, c1, c2, base)
    else:
        return _fullcopytracing(repo, c1, c2, base)

def _isfullcopytraceable(repo, c1, base):
    """ Checks that if base, source and destination are all no-public branches,
    if yes let's use the full copytrace algorithm for increased capabilities
    since it will be fast enough.

    `experimental.copytrace.sourcecommitlimit` can be used to set a limit for
    number of changesets from c1 to base such that if number of changesets are
    more than the limit, full copytracing algorithm won't be used.
    """
    if c1.rev() is None:
        c1 = c1.p1()
    if c1.mutable() and base.mutable():
        sourcecommitlimit = repo.ui.configint('experimental',
                                              'copytrace.sourcecommitlimit')
        commits = len(repo.revs('%d::%d', base.rev(), c1.rev()))
        return commits < sourcecommitlimit
    return False

def _checksinglesidecopies(src, dsts1, m1, m2, mb, c2, base,
                           copy, renamedelete):
    if src not in m2:
        # deleted on side 2
        if src not in m1:
            # renamed on side 1, deleted on side 2
            renamedelete[src] = dsts1
    elif m2[src] != mb[src]:
        if not _related(c2[src], base[src]):
            return
        # modified on side 2
        for dst in dsts1:
            if dst not in m2:
                # dst not added on side 2 (handle as regular
                # "both created" case in manifestmerge otherwise)
                copy[dst] = src

def _fullcopytracing(repo, c1, c2, base):
    """ The full copytracing algorithm which finds all the new files that were
    added from merge base up to the top commit and for each file it checks if
    this file was copied from another file.

    This is pretty slow when a lot of changesets are involved but will track all
    the copies.
    """
    m1 = c1.manifest()
    m2 = c2.manifest()
    mb = base.manifest()

    copies1 = pathcopies(base, c1)
    copies2 = pathcopies(base, c2)

    inversecopies1 = {}
    inversecopies2 = {}
    for dst, src in copies1.items():
        inversecopies1.setdefault(src, []).append(dst)
    for dst, src in copies2.items():
        inversecopies2.setdefault(src, []).append(dst)

    copy = {}
    diverge = {}
    renamedelete = {}
    allsources = set(inversecopies1) | set(inversecopies2)
    for src in allsources:
        dsts1 = inversecopies1.get(src)
        dsts2 = inversecopies2.get(src)
        if dsts1 and dsts2:
            # copied/renamed on both sides
            if src not in m1 and src not in m2:
                # renamed on both sides
                dsts1 = set(dsts1)
                dsts2 = set(dsts2)
                # If there's some overlap in the rename destinations, we
                # consider it not divergent. For example, if side 1 copies 'a'
                # to 'b' and 'c' and deletes 'a', and side 2 copies 'a' to 'c'
                # and 'd' and deletes 'a'.
                if dsts1 & dsts2:
                    for dst in (dsts1 & dsts2):
                        copy[dst] = src
                else:
                    diverge[src] = sorted(dsts1 | dsts2)
            elif src in m1 and src in m2:
                # copied on both sides
                dsts1 = set(dsts1)
                dsts2 = set(dsts2)
                for dst in (dsts1 & dsts2):
                    copy[dst] = src
            # TODO: Handle cases where it was renamed on one side and copied
            # on the other side
        elif dsts1:
            # copied/renamed only on side 1
            _checksinglesidecopies(src, dsts1, m1, m2, mb, c2, base,
                                   copy, renamedelete)
        elif dsts2:
            # copied/renamed only on side 2
            _checksinglesidecopies(src, dsts2, m2, m1, mb, c1, base,
                                   copy, renamedelete)

    renamedeleteset = set()
    divergeset = set()
    for dsts in diverge.values():
        divergeset.update(dsts)
    for dsts in renamedelete.values():
        renamedeleteset.update(dsts)

    # find interesting file sets from manifests
    addedinm1 = m1.filesnotin(mb, repo.narrowmatch())
    addedinm2 = m2.filesnotin(mb, repo.narrowmatch())
    u1 = sorted(addedinm1 - addedinm2)
    u2 = sorted(addedinm2 - addedinm1)

    header = "  unmatched files in %s"
    if u1:
        repo.ui.debug("%s:\n   %s\n" % (header % 'local', "\n   ".join(u1)))
    if u2:
        repo.ui.debug("%s:\n   %s\n" % (header % 'other', "\n   ".join(u2)))

    fullcopy = copies1.copy()
    fullcopy.update(copies2)
    if not fullcopy:
        return copy, {}, diverge, renamedelete, {}

    if repo.ui.debugflag:
        repo.ui.debug("  all copies found (* = to merge, ! = divergent, "
                      "% = renamed and deleted):\n")
        for f in sorted(fullcopy):
            note = ""
            if f in copy:
                note += "*"
            if f in divergeset:
                note += "!"
            if f in renamedeleteset:
                note += "%"
            repo.ui.debug("   src: '%s' -> dst: '%s' %s\n" % (fullcopy[f], f,
                                                              note))
    del divergeset

    repo.ui.debug("  checking for directory renames\n")

    # generate a directory move map
    d1, d2 = c1.dirs(), c2.dirs()
    invalid = set()
    dirmove = {}

    # examine each file copy for a potential directory move, which is
    # when all the files in a directory are moved to a new directory
    for dst, src in fullcopy.iteritems():
        dsrc, ddst = pathutil.dirname(src), pathutil.dirname(dst)
        if dsrc in invalid:
            # already seen to be uninteresting
            continue
        elif dsrc in d1 and ddst in d1:
            # directory wasn't entirely moved locally
            invalid.add(dsrc)
        elif dsrc in d2 and ddst in d2:
            # directory wasn't entirely moved remotely
            invalid.add(dsrc)
        elif dsrc in dirmove and dirmove[dsrc] != ddst:
            # files from the same directory moved to two different places
            invalid.add(dsrc)
        else:
            # looks good so far
            dirmove[dsrc] = ddst

    for i in invalid:
        if i in dirmove:
            del dirmove[i]
    del d1, d2, invalid

    if not dirmove:
        return copy, {}, diverge, renamedelete, {}

    dirmove = {k + "/": v + "/" for k, v in dirmove.iteritems()}

    for d in dirmove:
        repo.ui.debug("   discovered dir src: '%s' -> dst: '%s'\n" %
                      (d, dirmove[d]))

    movewithdir = {}
    # check unaccounted nonoverlapping files against directory moves
    for f in u1 + u2:
        if f not in fullcopy:
            for d in dirmove:
                if f.startswith(d):
                    # new file added in a directory that was moved, move it
                    df = dirmove[d] + f[len(d):]
                    if df not in copy:
                        movewithdir[f] = df
                        repo.ui.debug(("   pending file src: '%s' -> "
                                       "dst: '%s'\n") % (f, df))
                    break

    return copy, movewithdir, diverge, renamedelete, dirmove

def _heuristicscopytracing(repo, c1, c2, base):
    """ Fast copytracing using filename heuristics

    Assumes that moves or renames are of following two types:

    1) Inside a directory only (same directory name but different filenames)
    2) Move from one directory to another
                    (same filenames but different directory names)

    Works only when there are no merge commits in the "source branch".
    Source branch is commits from base up to c2 not including base.

    If merge is involved it fallbacks to _fullcopytracing().

    Can be used by setting the following config:

        [experimental]
        copytrace = heuristics

    In some cases the copy/move candidates found by heuristics can be very large
    in number and that will make the algorithm slow. The number of possible
    candidates to check can be limited by using the config
    `experimental.copytrace.movecandidateslimit` which defaults to 100.
    """

    if c1.rev() is None:
        c1 = c1.p1()
    if c2.rev() is None:
        c2 = c2.p1()

    copies = {}

    changedfiles = set()
    m1 = c1.manifest()
    if not repo.revs('%d::%d', base.rev(), c2.rev()):
        # If base is not in c2 branch, we switch to fullcopytracing
        repo.ui.debug("switching to full copytracing as base is not "
                      "an ancestor of c2\n")
        return _fullcopytracing(repo, c1, c2, base)

    ctx = c2
    while ctx != base:
        if len(ctx.parents()) == 2:
            # To keep things simple let's not handle merges
            repo.ui.debug("switching to full copytracing because of merges\n")
            return _fullcopytracing(repo, c1, c2, base)
        changedfiles.update(ctx.files())
        ctx = ctx.p1()

    cp = _forwardcopies(base, c2)
    for dst, src in cp.iteritems():
        if src in m1:
            copies[dst] = src

    # file is missing if it isn't present in the destination, but is present in
    # the base and present in the source.
    # Presence in the base is important to exclude added files, presence in the
    # source is important to exclude removed files.
    filt = lambda f: f not in m1 and f in base and f in c2
    missingfiles = [f for f in changedfiles if filt(f)]

    if missingfiles:
        basenametofilename = collections.defaultdict(list)
        dirnametofilename = collections.defaultdict(list)

        for f in m1.filesnotin(base.manifest()):
            basename = os.path.basename(f)
            dirname = os.path.dirname(f)
            basenametofilename[basename].append(f)
            dirnametofilename[dirname].append(f)

        for f in missingfiles:
            basename = os.path.basename(f)
            dirname = os.path.dirname(f)
            samebasename = basenametofilename[basename]
            samedirname = dirnametofilename[dirname]
            movecandidates = samebasename + samedirname
            # f is guaranteed to be present in c2, that's why
            # c2.filectx(f) won't fail
            f2 = c2.filectx(f)
            # we can have a lot of candidates which can slow down the heuristics
            # config value to limit the number of candidates moves to check
            maxcandidates = repo.ui.configint('experimental',
                                              'copytrace.movecandidateslimit')

            if len(movecandidates) > maxcandidates:
                repo.ui.status(_("skipping copytracing for '%s', more "
                                 "candidates than the limit: %d\n")
                               % (f, len(movecandidates)))
                continue

            for candidate in movecandidates:
                f1 = c1.filectx(candidate)
                if _related(f1, f2):
                    # if there are a few related copies then we'll merge
                    # changes into all of them. This matches the behaviour
                    # of upstream copytracing
                    copies[candidate] = f

    return copies, {}, {}, {}, {}

def _related(f1, f2):
    """return True if f1 and f2 filectx have a common ancestor

    Walk back to common ancestor to see if the two files originate
    from the same file. Since workingfilectx's rev() is None it messes
    up the integer comparison logic, hence the pre-step check for
    None (f1 and f2 can only be workingfilectx's initially).
    """

    if f1 == f2:
        return True # a match

    g1, g2 = f1.ancestors(), f2.ancestors()
    try:
        f1r, f2r = f1.linkrev(), f2.linkrev()

        if f1r is None:
            f1 = next(g1)
        if f2r is None:
            f2 = next(g2)

        while True:
            f1r, f2r = f1.linkrev(), f2.linkrev()
            if f1r > f2r:
                f1 = next(g1)
            elif f2r > f1r:
                f2 = next(g2)
            else: # f1 and f2 point to files in the same linkrev
                return f1 == f2 # true if they point to the same file
    except StopIteration:
        return False

def duplicatecopies(repo, wctx, rev, fromrev, skiprev=None):
    """reproduce copies from fromrev to rev in the dirstate

    If skiprev is specified, it's a revision that should be used to
    filter copy records. Any copies that occur between fromrev and
    skiprev will not be duplicated, even if they appear in the set of
    copies between fromrev and rev.
    """
    exclude = {}
    ctraceconfig = repo.ui.config('experimental', 'copytrace')
    bctrace = stringutil.parsebool(ctraceconfig)
    if (skiprev is not None and
        (ctraceconfig == 'heuristics' or bctrace or bctrace is None)):
        # copytrace='off' skips this line, but not the entire function because
        # the line below is O(size of the repo) during a rebase, while the rest
        # of the function is much faster (and is required for carrying copy
        # metadata across the rebase anyway).
        exclude = pathcopies(repo[fromrev], repo[skiprev])
    for dst, src in pathcopies(repo[fromrev], repo[rev]).iteritems():
        if dst in exclude:
            continue
        if dst in wctx:
            wctx[dst].markcopied(src)
