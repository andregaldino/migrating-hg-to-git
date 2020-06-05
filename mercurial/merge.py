# merge.py - directory-level update/merge handling for Mercurial
#
# Copyright 2006, 2007 Matt Mackall <mpm@selenic.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import errno
import stat
import struct

from .i18n import _
from .node import (
    addednodeid,
    modifiednodeid,
    nullid,
    nullrev,
)
from .thirdparty import attr
from . import (
    copies,
    encoding,
    error,
    filemerge,
    match as matchmod,
    mergestate as mergestatemod,
    obsutil,
    pathutil,
    pycompat,
    scmutil,
    subrepoutil,
    util,
    worker,
)

_pack = struct.pack
_unpack = struct.unpack


def _getcheckunknownconfig(repo, section, name):
    config = repo.ui.config(section, name)
    valid = [b'abort', b'ignore', b'warn']
    if config not in valid:
        validstr = b', '.join([b"'" + v + b"'" for v in valid])
        raise error.ConfigError(
            _(b"%s.%s not valid ('%s' is none of %s)")
            % (section, name, config, validstr)
        )
    return config


def _checkunknownfile(repo, wctx, mctx, f, f2=None):
    if wctx.isinmemory():
        # Nothing to do in IMM because nothing in the "working copy" can be an
        # unknown file.
        #
        # Note that we should bail out here, not in ``_checkunknownfiles()``,
        # because that function does other useful work.
        return False

    if f2 is None:
        f2 = f
    return (
        repo.wvfs.audit.check(f)
        and repo.wvfs.isfileorlink(f)
        and repo.dirstate.normalize(f) not in repo.dirstate
        and mctx[f2].cmp(wctx[f])
    )


class _unknowndirschecker(object):
    """
    Look for any unknown files or directories that may have a path conflict
    with a file.  If any path prefix of the file exists as a file or link,
    then it conflicts.  If the file itself is a directory that contains any
    file that is not tracked, then it conflicts.

    Returns the shortest path at which a conflict occurs, or None if there is
    no conflict.
    """

    def __init__(self):
        # A set of paths known to be good.  This prevents repeated checking of
        # dirs.  It will be updated with any new dirs that are checked and found
        # to be safe.
        self._unknowndircache = set()

        # A set of paths that are known to be absent.  This prevents repeated
        # checking of subdirectories that are known not to exist. It will be
        # updated with any new dirs that are checked and found to be absent.
        self._missingdircache = set()

    def __call__(self, repo, wctx, f):
        if wctx.isinmemory():
            # Nothing to do in IMM for the same reason as ``_checkunknownfile``.
            return False

        # Check for path prefixes that exist as unknown files.
        for p in reversed(list(pathutil.finddirs(f))):
            if p in self._missingdircache:
                return
            if p in self._unknowndircache:
                continue
            if repo.wvfs.audit.check(p):
                if (
                    repo.wvfs.isfileorlink(p)
                    and repo.dirstate.normalize(p) not in repo.dirstate
                ):
                    return p
                if not repo.wvfs.lexists(p):
                    self._missingdircache.add(p)
                    return
                self._unknowndircache.add(p)

        # Check if the file conflicts with a directory containing unknown files.
        if repo.wvfs.audit.check(f) and repo.wvfs.isdir(f):
            # Does the directory contain any files that are not in the dirstate?
            for p, dirs, files in repo.wvfs.walk(f):
                for fn in files:
                    relf = util.pconvert(repo.wvfs.reljoin(p, fn))
                    relf = repo.dirstate.normalize(relf, isknown=True)
                    if relf not in repo.dirstate:
                        return f
        return None


def _checkunknownfiles(repo, wctx, mctx, force, actions, mergeforce):
    """
    Considers any actions that care about the presence of conflicting unknown
    files. For some actions, the result is to abort; for others, it is to
    choose a different action.
    """
    fileconflicts = set()
    pathconflicts = set()
    warnconflicts = set()
    abortconflicts = set()
    unknownconfig = _getcheckunknownconfig(repo, b'merge', b'checkunknown')
    ignoredconfig = _getcheckunknownconfig(repo, b'merge', b'checkignored')
    pathconfig = repo.ui.configbool(
        b'experimental', b'merge.checkpathconflicts'
    )
    if not force:

        def collectconflicts(conflicts, config):
            if config == b'abort':
                abortconflicts.update(conflicts)
            elif config == b'warn':
                warnconflicts.update(conflicts)

        checkunknowndirs = _unknowndirschecker()
        for f, (m, args, msg) in pycompat.iteritems(actions):
            if m in (
                mergestatemod.ACTION_CREATED,
                mergestatemod.ACTION_DELETED_CHANGED,
            ):
                if _checkunknownfile(repo, wctx, mctx, f):
                    fileconflicts.add(f)
                elif pathconfig and f not in wctx:
                    path = checkunknowndirs(repo, wctx, f)
                    if path is not None:
                        pathconflicts.add(path)
            elif m == mergestatemod.ACTION_LOCAL_DIR_RENAME_GET:
                if _checkunknownfile(repo, wctx, mctx, f, args[0]):
                    fileconflicts.add(f)

        allconflicts = fileconflicts | pathconflicts
        ignoredconflicts = {c for c in allconflicts if repo.dirstate._ignore(c)}
        unknownconflicts = allconflicts - ignoredconflicts
        collectconflicts(ignoredconflicts, ignoredconfig)
        collectconflicts(unknownconflicts, unknownconfig)
    else:
        for f, (m, args, msg) in pycompat.iteritems(actions):
            if m == mergestatemod.ACTION_CREATED_MERGE:
                fl2, anc = args
                different = _checkunknownfile(repo, wctx, mctx, f)
                if repo.dirstate._ignore(f):
                    config = ignoredconfig
                else:
                    config = unknownconfig

                # The behavior when force is True is described by this table:
                #  config  different  mergeforce  |    action    backup
                #    *         n          *       |      get        n
                #    *         y          y       |     merge       -
                #   abort      y          n       |     merge       -   (1)
                #   warn       y          n       |  warn + get     y
                #  ignore      y          n       |      get        y
                #
                # (1) this is probably the wrong behavior here -- we should
                #     probably abort, but some actions like rebases currently
                #     don't like an abort happening in the middle of
                #     merge.update.
                if not different:
                    actions[f] = (
                        mergestatemod.ACTION_GET,
                        (fl2, False),
                        b'remote created',
                    )
                elif mergeforce or config == b'abort':
                    actions[f] = (
                        mergestatemod.ACTION_MERGE,
                        (f, f, None, False, anc),
                        b'remote differs from untracked local',
                    )
                elif config == b'abort':
                    abortconflicts.add(f)
                else:
                    if config == b'warn':
                        warnconflicts.add(f)
                    actions[f] = (
                        mergestatemod.ACTION_GET,
                        (fl2, True),
                        b'remote created',
                    )

    for f in sorted(abortconflicts):
        warn = repo.ui.warn
        if f in pathconflicts:
            if repo.wvfs.isfileorlink(f):
                warn(_(b"%s: untracked file conflicts with directory\n") % f)
            else:
                warn(_(b"%s: untracked directory conflicts with file\n") % f)
        else:
            warn(_(b"%s: untracked file differs\n") % f)
    if abortconflicts:
        raise error.Abort(
            _(
                b"untracked files in working directory "
                b"differ from files in requested revision"
            )
        )

    for f in sorted(warnconflicts):
        if repo.wvfs.isfileorlink(f):
            repo.ui.warn(_(b"%s: replacing untracked file\n") % f)
        else:
            repo.ui.warn(_(b"%s: replacing untracked files in directory\n") % f)

    for f, (m, args, msg) in pycompat.iteritems(actions):
        if m == mergestatemod.ACTION_CREATED:
            backup = (
                f in fileconflicts
                or f in pathconflicts
                or any(p in pathconflicts for p in pathutil.finddirs(f))
            )
            (flags,) = args
            actions[f] = (mergestatemod.ACTION_GET, (flags, backup), msg)


def _forgetremoved(wctx, mctx, branchmerge):
    """
    Forget removed files

    If we're jumping between revisions (as opposed to merging), and if
    neither the working directory nor the target rev has the file,
    then we need to remove it from the dirstate, to prevent the
    dirstate from listing the file when it is no longer in the
    manifest.

    If we're merging, and the other revision has removed a file
    that is not present in the working directory, we need to mark it
    as removed.
    """

    actions = {}
    m = mergestatemod.ACTION_FORGET
    if branchmerge:
        m = mergestatemod.ACTION_REMOVE
    for f in wctx.deleted():
        if f not in mctx:
            actions[f] = m, None, b"forget deleted"

    if not branchmerge:
        for f in wctx.removed():
            if f not in mctx:
                actions[f] = (
                    mergestatemod.ACTION_FORGET,
                    None,
                    b"forget removed",
                )

    return actions


def _checkcollision(repo, wmf, actions):
    """
    Check for case-folding collisions.
    """
    # If the repo is narrowed, filter out files outside the narrowspec.
    narrowmatch = repo.narrowmatch()
    if not narrowmatch.always():
        pmmf = set(wmf.walk(narrowmatch))
        if actions:
            narrowactions = {}
            for m, actionsfortype in pycompat.iteritems(actions):
                narrowactions[m] = []
                for (f, args, msg) in actionsfortype:
                    if narrowmatch(f):
                        narrowactions[m].append((f, args, msg))
            actions = narrowactions
    else:
        # build provisional merged manifest up
        pmmf = set(wmf)

    if actions:
        # KEEP and EXEC are no-op
        for m in (
            mergestatemod.ACTION_ADD,
            mergestatemod.ACTION_ADD_MODIFIED,
            mergestatemod.ACTION_FORGET,
            mergestatemod.ACTION_GET,
            mergestatemod.ACTION_CHANGED_DELETED,
            mergestatemod.ACTION_DELETED_CHANGED,
        ):
            for f, args, msg in actions[m]:
                pmmf.add(f)
        for f, args, msg in actions[mergestatemod.ACTION_REMOVE]:
            pmmf.discard(f)
        for f, args, msg in actions[mergestatemod.ACTION_DIR_RENAME_MOVE_LOCAL]:
            f2, flags = args
            pmmf.discard(f2)
            pmmf.add(f)
        for f, args, msg in actions[mergestatemod.ACTION_LOCAL_DIR_RENAME_GET]:
            pmmf.add(f)
        for f, args, msg in actions[mergestatemod.ACTION_MERGE]:
            f1, f2, fa, move, anc = args
            if move:
                pmmf.discard(f1)
            pmmf.add(f)

    # check case-folding collision in provisional merged manifest
    foldmap = {}
    for f in pmmf:
        fold = util.normcase(f)
        if fold in foldmap:
            raise error.Abort(
                _(b"case-folding collision between %s and %s")
                % (f, foldmap[fold])
            )
        foldmap[fold] = f

    # check case-folding of directories
    foldprefix = unfoldprefix = lastfull = b''
    for fold, f in sorted(foldmap.items()):
        if fold.startswith(foldprefix) and not f.startswith(unfoldprefix):
            # the folded prefix matches but actual casing is different
            raise error.Abort(
                _(b"case-folding collision between %s and directory of %s")
                % (lastfull, f)
            )
        foldprefix = fold + b'/'
        unfoldprefix = f + b'/'
        lastfull = f


def driverpreprocess(repo, ms, wctx, labels=None):
    """run the preprocess step of the merge driver, if any

    This is currently not implemented -- it's an extension point."""
    return True


def driverconclude(repo, ms, wctx, labels=None):
    """run the conclude step of the merge driver, if any

    This is currently not implemented -- it's an extension point."""
    return True


def _filesindirs(repo, manifest, dirs):
    """
    Generator that yields pairs of all the files in the manifest that are found
    inside the directories listed in dirs, and which directory they are found
    in.
    """
    for f in manifest:
        for p in pathutil.finddirs(f):
            if p in dirs:
                yield f, p
                break


def checkpathconflicts(repo, wctx, mctx, actions):
    """
    Check if any actions introduce path conflicts in the repository, updating
    actions to record or handle the path conflict accordingly.
    """
    mf = wctx.manifest()

    # The set of local files that conflict with a remote directory.
    localconflicts = set()

    # The set of directories that conflict with a remote file, and so may cause
    # conflicts if they still contain any files after the merge.
    remoteconflicts = set()

    # The set of directories that appear as both a file and a directory in the
    # remote manifest.  These indicate an invalid remote manifest, which
    # can't be updated to cleanly.
    invalidconflicts = set()

    # The set of directories that contain files that are being created.
    createdfiledirs = set()

    # The set of files deleted by all the actions.
    deletedfiles = set()

    for f, (m, args, msg) in actions.items():
        if m in (
            mergestatemod.ACTION_CREATED,
            mergestatemod.ACTION_DELETED_CHANGED,
            mergestatemod.ACTION_MERGE,
            mergestatemod.ACTION_CREATED_MERGE,
        ):
            # This action may create a new local file.
            createdfiledirs.update(pathutil.finddirs(f))
            if mf.hasdir(f):
                # The file aliases a local directory.  This might be ok if all
                # the files in the local directory are being deleted.  This
                # will be checked once we know what all the deleted files are.
                remoteconflicts.add(f)
        # Track the names of all deleted files.
        if m == mergestatemod.ACTION_REMOVE:
            deletedfiles.add(f)
        if m == mergestatemod.ACTION_MERGE:
            f1, f2, fa, move, anc = args
            if move:
                deletedfiles.add(f1)
        if m == mergestatemod.ACTION_DIR_RENAME_MOVE_LOCAL:
            f2, flags = args
            deletedfiles.add(f2)

    # Check all directories that contain created files for path conflicts.
    for p in createdfiledirs:
        if p in mf:
            if p in mctx:
                # A file is in a directory which aliases both a local
                # and a remote file.  This is an internal inconsistency
                # within the remote manifest.
                invalidconflicts.add(p)
            else:
                # A file is in a directory which aliases a local file.
                # We will need to rename the local file.
                localconflicts.add(p)
        if p in actions and actions[p][0] in (
            mergestatemod.ACTION_CREATED,
            mergestatemod.ACTION_DELETED_CHANGED,
            mergestatemod.ACTION_MERGE,
            mergestatemod.ACTION_CREATED_MERGE,
        ):
            # The file is in a directory which aliases a remote file.
            # This is an internal inconsistency within the remote
            # manifest.
            invalidconflicts.add(p)

    # Rename all local conflicting files that have not been deleted.
    for p in localconflicts:
        if p not in deletedfiles:
            ctxname = bytes(wctx).rstrip(b'+')
            pnew = util.safename(p, ctxname, wctx, set(actions.keys()))
            porig = wctx[p].copysource() or p
            actions[pnew] = (
                mergestatemod.ACTION_PATH_CONFLICT_RESOLVE,
                (p, porig),
                b'local path conflict',
            )
            actions[p] = (
                mergestatemod.ACTION_PATH_CONFLICT,
                (pnew, b'l'),
                b'path conflict',
            )

    if remoteconflicts:
        # Check if all files in the conflicting directories have been removed.
        ctxname = bytes(mctx).rstrip(b'+')
        for f, p in _filesindirs(repo, mf, remoteconflicts):
            if f not in deletedfiles:
                m, args, msg = actions[p]
                pnew = util.safename(p, ctxname, wctx, set(actions.keys()))
                if m in (
                    mergestatemod.ACTION_DELETED_CHANGED,
                    mergestatemod.ACTION_MERGE,
                ):
                    # Action was merge, just update target.
                    actions[pnew] = (m, args, msg)
                else:
                    # Action was create, change to renamed get action.
                    fl = args[0]
                    actions[pnew] = (
                        mergestatemod.ACTION_LOCAL_DIR_RENAME_GET,
                        (p, fl),
                        b'remote path conflict',
                    )
                actions[p] = (
                    mergestatemod.ACTION_PATH_CONFLICT,
                    (pnew, mergestatemod.ACTION_REMOVE),
                    b'path conflict',
                )
                remoteconflicts.remove(p)
                break

    if invalidconflicts:
        for p in invalidconflicts:
            repo.ui.warn(_(b"%s: is both a file and a directory\n") % p)
        raise error.Abort(_(b"destination manifest contains path conflicts"))


def _filternarrowactions(narrowmatch, branchmerge, actions):
    """
    Filters out actions that can ignored because the repo is narrowed.

    Raise an exception if the merge cannot be completed because the repo is
    narrowed.
    """
    nooptypes = {b'k'}  # TODO: handle with nonconflicttypes
    nonconflicttypes = set(b'a am c cm f g gs r e'.split())
    # We mutate the items in the dict during iteration, so iterate
    # over a copy.
    for f, action in list(actions.items()):
        if narrowmatch(f):
            pass
        elif not branchmerge:
            del actions[f]  # just updating, ignore changes outside clone
        elif action[0] in nooptypes:
            del actions[f]  # merge does not affect file
        elif action[0] in nonconflicttypes:
            raise error.Abort(
                _(
                    b'merge affects file \'%s\' outside narrow, '
                    b'which is not yet supported'
                )
                % f,
                hint=_(b'merging in the other direction may work'),
            )
        else:
            raise error.Abort(
                _(b'conflict in file \'%s\' is outside narrow clone') % f
            )


def manifestmerge(
    repo,
    wctx,
    p2,
    pa,
    branchmerge,
    force,
    matcher,
    acceptremote,
    followcopies,
    forcefulldiff=False,
):
    """
    Merge wctx and p2 with ancestor pa and generate merge action list

    branchmerge and force are as passed in to update
    matcher = matcher to filter file lists
    acceptremote = accept the incoming changes without prompting
    """
    if matcher is not None and matcher.always():
        matcher = None

    # manifests fetched in order are going to be faster, so prime the caches
    [
        x.manifest()
        for x in sorted(wctx.parents() + [p2, pa], key=scmutil.intrev)
    ]

    branch_copies1 = copies.branch_copies()
    branch_copies2 = copies.branch_copies()
    diverge = {}
    if followcopies:
        branch_copies1, branch_copies2, diverge = copies.mergecopies(
            repo, wctx, p2, pa
        )

    boolbm = pycompat.bytestr(bool(branchmerge))
    boolf = pycompat.bytestr(bool(force))
    boolm = pycompat.bytestr(bool(matcher))
    repo.ui.note(_(b"resolving manifests\n"))
    repo.ui.debug(
        b" branchmerge: %s, force: %s, partial: %s\n" % (boolbm, boolf, boolm)
    )
    repo.ui.debug(b" ancestor: %s, local: %s, remote: %s\n" % (pa, wctx, p2))

    m1, m2, ma = wctx.manifest(), p2.manifest(), pa.manifest()
    copied1 = set(branch_copies1.copy.values())
    copied1.update(branch_copies1.movewithdir.values())
    copied2 = set(branch_copies2.copy.values())
    copied2.update(branch_copies2.movewithdir.values())

    if b'.hgsubstate' in m1 and wctx.rev() is None:
        # Check whether sub state is modified, and overwrite the manifest
        # to flag the change. If wctx is a committed revision, we shouldn't
        # care for the dirty state of the working directory.
        if any(wctx.sub(s).dirty() for s in wctx.substate):
            m1[b'.hgsubstate'] = modifiednodeid

    # Don't use m2-vs-ma optimization if:
    # - ma is the same as m1 or m2, which we're just going to diff again later
    # - The caller specifically asks for a full diff, which is useful during bid
    #   merge.
    if pa not in ([wctx, p2] + wctx.parents()) and not forcefulldiff:
        # Identify which files are relevant to the merge, so we can limit the
        # total m1-vs-m2 diff to just those files. This has significant
        # performance benefits in large repositories.
        relevantfiles = set(ma.diff(m2).keys())

        # For copied and moved files, we need to add the source file too.
        for copykey, copyvalue in pycompat.iteritems(branch_copies1.copy):
            if copyvalue in relevantfiles:
                relevantfiles.add(copykey)
        for movedirkey in branch_copies1.movewithdir:
            relevantfiles.add(movedirkey)
        filesmatcher = scmutil.matchfiles(repo, relevantfiles)
        matcher = matchmod.intersectmatchers(matcher, filesmatcher)

    diff = m1.diff(m2, match=matcher)

    actions = {}
    for f, ((n1, fl1), (n2, fl2)) in pycompat.iteritems(diff):
        if n1 and n2:  # file exists on both local and remote side
            if f not in ma:
                # TODO: what if they're renamed from different sources?
                fa = branch_copies1.copy.get(
                    f, None
                ) or branch_copies2.copy.get(f, None)
                if fa is not None:
                    actions[f] = (
                        mergestatemod.ACTION_MERGE,
                        (f, f, fa, False, pa.node()),
                        b'both renamed from %s' % fa,
                    )
                else:
                    actions[f] = (
                        mergestatemod.ACTION_MERGE,
                        (f, f, None, False, pa.node()),
                        b'both created',
                    )
            else:
                a = ma[f]
                fla = ma.flags(f)
                nol = b'l' not in fl1 + fl2 + fla
                if n2 == a and fl2 == fla:
                    actions[f] = (
                        mergestatemod.ACTION_KEEP,
                        (),
                        b'remote unchanged',
                    )
                elif n1 == a and fl1 == fla:  # local unchanged - use remote
                    if n1 == n2:  # optimization: keep local content
                        actions[f] = (
                            mergestatemod.ACTION_EXEC,
                            (fl2,),
                            b'update permissions',
                        )
                    else:
                        actions[f] = (
                            mergestatemod.ACTION_GET_OTHER_AND_STORE
                            if branchmerge
                            else mergestatemod.ACTION_GET,
                            (fl2, False),
                            b'remote is newer',
                        )
                elif nol and n2 == a:  # remote only changed 'x'
                    actions[f] = (
                        mergestatemod.ACTION_EXEC,
                        (fl2,),
                        b'update permissions',
                    )
                elif nol and n1 == a:  # local only changed 'x'
                    actions[f] = (
                        mergestatemod.ACTION_GET_OTHER_AND_STORE
                        if branchmerge
                        else mergestatemod.ACTION_GET,
                        (fl1, False),
                        b'remote is newer',
                    )
                else:  # both changed something
                    actions[f] = (
                        mergestatemod.ACTION_MERGE,
                        (f, f, f, False, pa.node()),
                        b'versions differ',
                    )
        elif n1:  # file exists only on local side
            if f in copied2:
                pass  # we'll deal with it on m2 side
            elif (
                f in branch_copies1.movewithdir
            ):  # directory rename, move local
                f2 = branch_copies1.movewithdir[f]
                if f2 in m2:
                    actions[f2] = (
                        mergestatemod.ACTION_MERGE,
                        (f, f2, None, True, pa.node()),
                        b'remote directory rename, both created',
                    )
                else:
                    actions[f2] = (
                        mergestatemod.ACTION_DIR_RENAME_MOVE_LOCAL,
                        (f, fl1),
                        b'remote directory rename - move from %s' % f,
                    )
            elif f in branch_copies1.copy:
                f2 = branch_copies1.copy[f]
                actions[f] = (
                    mergestatemod.ACTION_MERGE,
                    (f, f2, f2, False, pa.node()),
                    b'local copied/moved from %s' % f2,
                )
            elif f in ma:  # clean, a different, no remote
                if n1 != ma[f]:
                    if acceptremote:
                        actions[f] = (
                            mergestatemod.ACTION_REMOVE,
                            None,
                            b'remote delete',
                        )
                    else:
                        actions[f] = (
                            mergestatemod.ACTION_CHANGED_DELETED,
                            (f, None, f, False, pa.node()),
                            b'prompt changed/deleted',
                        )
                elif n1 == addednodeid:
                    # This extra 'a' is added by working copy manifest to mark
                    # the file as locally added. We should forget it instead of
                    # deleting it.
                    actions[f] = (
                        mergestatemod.ACTION_FORGET,
                        None,
                        b'remote deleted',
                    )
                else:
                    actions[f] = (
                        mergestatemod.ACTION_REMOVE,
                        None,
                        b'other deleted',
                    )
        elif n2:  # file exists only on remote side
            if f in copied1:
                pass  # we'll deal with it on m1 side
            elif f in branch_copies2.movewithdir:
                f2 = branch_copies2.movewithdir[f]
                if f2 in m1:
                    actions[f2] = (
                        mergestatemod.ACTION_MERGE,
                        (f2, f, None, False, pa.node()),
                        b'local directory rename, both created',
                    )
                else:
                    actions[f2] = (
                        mergestatemod.ACTION_LOCAL_DIR_RENAME_GET,
                        (f, fl2),
                        b'local directory rename - get from %s' % f,
                    )
            elif f in branch_copies2.copy:
                f2 = branch_copies2.copy[f]
                if f2 in m2:
                    actions[f] = (
                        mergestatemod.ACTION_MERGE,
                        (f2, f, f2, False, pa.node()),
                        b'remote copied from %s' % f2,
                    )
                else:
                    actions[f] = (
                        mergestatemod.ACTION_MERGE,
                        (f2, f, f2, True, pa.node()),
                        b'remote moved from %s' % f2,
                    )
            elif f not in ma:
                # local unknown, remote created: the logic is described by the
                # following table:
                #
                # force  branchmerge  different  |  action
                #   n         *           *      |   create
                #   y         n           *      |   create
                #   y         y           n      |   create
                #   y         y           y      |   merge
                #
                # Checking whether the files are different is expensive, so we
                # don't do that when we can avoid it.
                if not force:
                    actions[f] = (
                        mergestatemod.ACTION_CREATED,
                        (fl2,),
                        b'remote created',
                    )
                elif not branchmerge:
                    actions[f] = (
                        mergestatemod.ACTION_CREATED,
                        (fl2,),
                        b'remote created',
                    )
                else:
                    actions[f] = (
                        mergestatemod.ACTION_CREATED_MERGE,
                        (fl2, pa.node()),
                        b'remote created, get or merge',
                    )
            elif n2 != ma[f]:
                df = None
                for d in branch_copies1.dirmove:
                    if f.startswith(d):
                        # new file added in a directory that was moved
                        df = branch_copies1.dirmove[d] + f[len(d) :]
                        break
                if df is not None and df in m1:
                    actions[df] = (
                        mergestatemod.ACTION_MERGE,
                        (df, f, f, False, pa.node()),
                        b'local directory rename - respect move '
                        b'from %s' % f,
                    )
                elif acceptremote:
                    actions[f] = (
                        mergestatemod.ACTION_CREATED,
                        (fl2,),
                        b'remote recreating',
                    )
                else:
                    actions[f] = (
                        mergestatemod.ACTION_DELETED_CHANGED,
                        (None, f, f, False, pa.node()),
                        b'prompt deleted/changed',
                    )

    if repo.ui.configbool(b'experimental', b'merge.checkpathconflicts'):
        # If we are merging, look for path conflicts.
        checkpathconflicts(repo, wctx, p2, actions)

    narrowmatch = repo.narrowmatch()
    if not narrowmatch.always():
        # Updates "actions" in place
        _filternarrowactions(narrowmatch, branchmerge, actions)

    renamedelete = branch_copies1.renamedelete
    renamedelete.update(branch_copies2.renamedelete)

    return actions, diverge, renamedelete


def _resolvetrivial(repo, wctx, mctx, ancestor, actions):
    """Resolves false conflicts where the nodeid changed but the content
       remained the same."""
    # We force a copy of actions.items() because we're going to mutate
    # actions as we resolve trivial conflicts.
    for f, (m, args, msg) in list(actions.items()):
        if (
            m == mergestatemod.ACTION_CHANGED_DELETED
            and f in ancestor
            and not wctx[f].cmp(ancestor[f])
        ):
            # local did change but ended up with same content
            actions[f] = mergestatemod.ACTION_REMOVE, None, b'prompt same'
        elif (
            m == mergestatemod.ACTION_DELETED_CHANGED
            and f in ancestor
            and not mctx[f].cmp(ancestor[f])
        ):
            # remote did change but ended up with same content
            del actions[f]  # don't get = keep local deleted


def calculateupdates(
    repo,
    wctx,
    mctx,
    ancestors,
    branchmerge,
    force,
    acceptremote,
    followcopies,
    matcher=None,
    mergeforce=False,
):
    """Calculate the actions needed to merge mctx into wctx using ancestors"""
    # Avoid cycle.
    from . import sparse

    if len(ancestors) == 1:  # default
        actions, diverge, renamedelete = manifestmerge(
            repo,
            wctx,
            mctx,
            ancestors[0],
            branchmerge,
            force,
            matcher,
            acceptremote,
            followcopies,
        )
        _checkunknownfiles(repo, wctx, mctx, force, actions, mergeforce)

    else:  # only when merge.preferancestor=* - the default
        repo.ui.note(
            _(b"note: merging %s and %s using bids from ancestors %s\n")
            % (
                wctx,
                mctx,
                _(b' and ').join(pycompat.bytestr(anc) for anc in ancestors),
            )
        )

        # Call for bids
        fbids = (
            {}
        )  # mapping filename to bids (action method to list af actions)
        diverge, renamedelete = None, None
        for ancestor in ancestors:
            repo.ui.note(_(b'\ncalculating bids for ancestor %s\n') % ancestor)
            actions, diverge1, renamedelete1 = manifestmerge(
                repo,
                wctx,
                mctx,
                ancestor,
                branchmerge,
                force,
                matcher,
                acceptremote,
                followcopies,
                forcefulldiff=True,
            )
            _checkunknownfiles(repo, wctx, mctx, force, actions, mergeforce)

            # Track the shortest set of warning on the theory that bid
            # merge will correctly incorporate more information
            if diverge is None or len(diverge1) < len(diverge):
                diverge = diverge1
            if renamedelete is None or len(renamedelete) < len(renamedelete1):
                renamedelete = renamedelete1

            for f, a in sorted(pycompat.iteritems(actions)):
                m, args, msg = a
                if m == mergestatemod.ACTION_GET_OTHER_AND_STORE:
                    m = mergestatemod.ACTION_GET
                repo.ui.debug(b' %s: %s -> %s\n' % (f, msg, m))
                if f in fbids:
                    d = fbids[f]
                    if m in d:
                        d[m].append(a)
                    else:
                        d[m] = [a]
                else:
                    fbids[f] = {m: [a]}

        # Pick the best bid for each file
        repo.ui.note(_(b'\nauction for merging merge bids\n'))
        actions = {}
        for f, bids in sorted(fbids.items()):
            # bids is a mapping from action method to list af actions
            # Consensus?
            if len(bids) == 1:  # all bids are the same kind of method
                m, l = list(bids.items())[0]
                if all(a == l[0] for a in l[1:]):  # len(bids) is > 1
                    repo.ui.note(_(b" %s: consensus for %s\n") % (f, m))
                    actions[f] = l[0]
                    continue
            # If keep is an option, just do it.
            if mergestatemod.ACTION_KEEP in bids:
                repo.ui.note(_(b" %s: picking 'keep' action\n") % f)
                actions[f] = bids[mergestatemod.ACTION_KEEP][0]
                continue
            # If there are gets and they all agree [how could they not?], do it.
            if mergestatemod.ACTION_GET in bids:
                ga0 = bids[mergestatemod.ACTION_GET][0]
                if all(a == ga0 for a in bids[mergestatemod.ACTION_GET][1:]):
                    repo.ui.note(_(b" %s: picking 'get' action\n") % f)
                    actions[f] = ga0
                    continue
            # TODO: Consider other simple actions such as mode changes
            # Handle inefficient democrazy.
            repo.ui.note(_(b' %s: multiple bids for merge action:\n') % f)
            for m, l in sorted(bids.items()):
                for _f, args, msg in l:
                    repo.ui.note(b'  %s -> %s\n' % (msg, m))
            # Pick random action. TODO: Instead, prompt user when resolving
            m, l = list(bids.items())[0]
            repo.ui.warn(
                _(b' %s: ambiguous merge - picked %s action\n') % (f, m)
            )
            actions[f] = l[0]
            continue
        repo.ui.note(_(b'end of auction\n\n'))

    if wctx.rev() is None:
        fractions = _forgetremoved(wctx, mctx, branchmerge)
        actions.update(fractions)

    prunedactions = sparse.filterupdatesactions(
        repo, wctx, mctx, branchmerge, actions
    )
    _resolvetrivial(repo, wctx, mctx, ancestors[0], actions)

    return prunedactions, diverge, renamedelete


def _getcwd():
    try:
        return encoding.getcwd()
    except OSError as err:
        if err.errno == errno.ENOENT:
            return None
        raise


def batchremove(repo, wctx, actions):
    """apply removes to the working directory

    yields tuples for progress updates
    """
    verbose = repo.ui.verbose
    cwd = _getcwd()
    i = 0
    for f, args, msg in actions:
        repo.ui.debug(b" %s: %s -> r\n" % (f, msg))
        if verbose:
            repo.ui.note(_(b"removing %s\n") % f)
        wctx[f].audit()
        try:
            wctx[f].remove(ignoremissing=True)
        except OSError as inst:
            repo.ui.warn(
                _(b"update failed to remove %s: %s!\n") % (f, inst.strerror)
            )
        if i == 100:
            yield i, f
            i = 0
        i += 1
    if i > 0:
        yield i, f

    if cwd and not _getcwd():
        # cwd was removed in the course of removing files; print a helpful
        # warning.
        repo.ui.warn(
            _(
                b"current directory was removed\n"
                b"(consider changing to repo root: %s)\n"
            )
            % repo.root
        )


def batchget(repo, mctx, wctx, wantfiledata, actions):
    """apply gets to the working directory

    mctx is the context to get from

    Yields arbitrarily many (False, tuple) for progress updates, followed by
    exactly one (True, filedata). When wantfiledata is false, filedata is an
    empty dict. When wantfiledata is true, filedata[f] is a triple (mode, size,
    mtime) of the file f written for each action.
    """
    filedata = {}
    verbose = repo.ui.verbose
    fctx = mctx.filectx
    ui = repo.ui
    i = 0
    with repo.wvfs.backgroundclosing(ui, expectedcount=len(actions)):
        for f, (flags, backup), msg in actions:
            repo.ui.debug(b" %s: %s -> g\n" % (f, msg))
            if verbose:
                repo.ui.note(_(b"getting %s\n") % f)

            if backup:
                # If a file or directory exists with the same name, back that
                # up.  Otherwise, look to see if there is a file that conflicts
                # with a directory this file is in, and if so, back that up.
                conflicting = f
                if not repo.wvfs.lexists(f):
                    for p in pathutil.finddirs(f):
                        if repo.wvfs.isfileorlink(p):
                            conflicting = p
                            break
                if repo.wvfs.lexists(conflicting):
                    orig = scmutil.backuppath(ui, repo, conflicting)
                    util.rename(repo.wjoin(conflicting), orig)
            wfctx = wctx[f]
            wfctx.clearunknown()
            atomictemp = ui.configbool(b"experimental", b"update.atomic-file")
            size = wfctx.write(
                fctx(f).data(),
                flags,
                backgroundclose=True,
                atomictemp=atomictemp,
            )
            if wantfiledata:
                s = wfctx.lstat()
                mode = s.st_mode
                mtime = s[stat.ST_MTIME]
                filedata[f] = (mode, size, mtime)  # for dirstate.normal
            if i == 100:
                yield False, (i, f)
                i = 0
            i += 1
    if i > 0:
        yield False, (i, f)
    yield True, filedata


def _prefetchfiles(repo, ctx, actions):
    """Invoke ``scmutil.prefetchfiles()`` for the files relevant to the dict
    of merge actions.  ``ctx`` is the context being merged in."""

    # Skipping 'a', 'am', 'f', 'r', 'dm', 'e', 'k', 'p' and 'pr', because they
    # don't touch the context to be merged in.  'cd' is skipped, because
    # changed/deleted never resolves to something from the remote side.
    oplist = [
        actions[a]
        for a in (
            mergestatemod.ACTION_GET,
            mergestatemod.ACTION_DELETED_CHANGED,
            mergestatemod.ACTION_LOCAL_DIR_RENAME_GET,
            mergestatemod.ACTION_MERGE,
        )
    ]
    prefetch = scmutil.prefetchfiles
    matchfiles = scmutil.matchfiles
    prefetch(
        repo,
        [ctx.rev()],
        matchfiles(repo, [f for sublist in oplist for f, args, msg in sublist]),
    )


@attr.s(frozen=True)
class updateresult(object):
    updatedcount = attr.ib()
    mergedcount = attr.ib()
    removedcount = attr.ib()
    unresolvedcount = attr.ib()

    def isempty(self):
        return not (
            self.updatedcount
            or self.mergedcount
            or self.removedcount
            or self.unresolvedcount
        )


def emptyactions():
    """create an actions dict, to be populated and passed to applyupdates()"""
    return {
        m: []
        for m in (
            mergestatemod.ACTION_ADD,
            mergestatemod.ACTION_ADD_MODIFIED,
            mergestatemod.ACTION_FORGET,
            mergestatemod.ACTION_GET,
            mergestatemod.ACTION_CHANGED_DELETED,
            mergestatemod.ACTION_DELETED_CHANGED,
            mergestatemod.ACTION_REMOVE,
            mergestatemod.ACTION_DIR_RENAME_MOVE_LOCAL,
            mergestatemod.ACTION_LOCAL_DIR_RENAME_GET,
            mergestatemod.ACTION_MERGE,
            mergestatemod.ACTION_EXEC,
            mergestatemod.ACTION_KEEP,
            mergestatemod.ACTION_PATH_CONFLICT,
            mergestatemod.ACTION_PATH_CONFLICT_RESOLVE,
            mergestatemod.ACTION_GET_OTHER_AND_STORE,
        )
    }


def applyupdates(
    repo, actions, wctx, mctx, overwrite, wantfiledata, labels=None
):
    """apply the merge action list to the working directory

    wctx is the working copy context
    mctx is the context to be merged into the working copy

    Return a tuple of (counts, filedata), where counts is a tuple
    (updated, merged, removed, unresolved) that describes how many
    files were affected by the update, and filedata is as described in
    batchget.
    """

    _prefetchfiles(repo, mctx, actions)

    updated, merged, removed = 0, 0, 0
    ms = mergestatemod.mergestate.clean(
        repo, wctx.p1().node(), mctx.node(), labels
    )

    # add ACTION_GET_OTHER_AND_STORE to mergestate
    for e in actions[mergestatemod.ACTION_GET_OTHER_AND_STORE]:
        ms.addmergedother(e[0])

    moves = []
    for m, l in actions.items():
        l.sort()

    # 'cd' and 'dc' actions are treated like other merge conflicts
    mergeactions = sorted(actions[mergestatemod.ACTION_CHANGED_DELETED])
    mergeactions.extend(sorted(actions[mergestatemod.ACTION_DELETED_CHANGED]))
    mergeactions.extend(actions[mergestatemod.ACTION_MERGE])
    for f, args, msg in mergeactions:
        f1, f2, fa, move, anc = args
        if f == b'.hgsubstate':  # merged internally
            continue
        if f1 is None:
            fcl = filemerge.absentfilectx(wctx, fa)
        else:
            repo.ui.debug(b" preserving %s for resolve of %s\n" % (f1, f))
            fcl = wctx[f1]
        if f2 is None:
            fco = filemerge.absentfilectx(mctx, fa)
        else:
            fco = mctx[f2]
        actx = repo[anc]
        if fa in actx:
            fca = actx[fa]
        else:
            # TODO: move to absentfilectx
            fca = repo.filectx(f1, fileid=nullrev)
        ms.add(fcl, fco, fca, f)
        if f1 != f and move:
            moves.append(f1)

    # remove renamed files after safely stored
    for f in moves:
        if wctx[f].lexists():
            repo.ui.debug(b"removing %s\n" % f)
            wctx[f].audit()
            wctx[f].remove()

    numupdates = sum(
        len(l) for m, l in actions.items() if m != mergestatemod.ACTION_KEEP
    )
    progress = repo.ui.makeprogress(
        _(b'updating'), unit=_(b'files'), total=numupdates
    )

    if [
        a
        for a in actions[mergestatemod.ACTION_REMOVE]
        if a[0] == b'.hgsubstate'
    ]:
        subrepoutil.submerge(repo, wctx, mctx, wctx, overwrite, labels)

    # record path conflicts
    for f, args, msg in actions[mergestatemod.ACTION_PATH_CONFLICT]:
        f1, fo = args
        s = repo.ui.status
        s(
            _(
                b"%s: path conflict - a file or link has the same name as a "
                b"directory\n"
            )
            % f
        )
        if fo == b'l':
            s(_(b"the local file has been renamed to %s\n") % f1)
        else:
            s(_(b"the remote file has been renamed to %s\n") % f1)
        s(_(b"resolve manually then use 'hg resolve --mark %s'\n") % f)
        ms.addpath(f, f1, fo)
        progress.increment(item=f)

    # When merging in-memory, we can't support worker processes, so set the
    # per-item cost at 0 in that case.
    cost = 0 if wctx.isinmemory() else 0.001

    # remove in parallel (must come before resolving path conflicts and getting)
    prog = worker.worker(
        repo.ui,
        cost,
        batchremove,
        (repo, wctx),
        actions[mergestatemod.ACTION_REMOVE],
    )
    for i, item in prog:
        progress.increment(step=i, item=item)
    removed = len(actions[mergestatemod.ACTION_REMOVE])

    # resolve path conflicts (must come before getting)
    for f, args, msg in actions[mergestatemod.ACTION_PATH_CONFLICT_RESOLVE]:
        repo.ui.debug(b" %s: %s -> pr\n" % (f, msg))
        (f0, origf0) = args
        if wctx[f0].lexists():
            repo.ui.note(_(b"moving %s to %s\n") % (f0, f))
            wctx[f].audit()
            wctx[f].write(wctx.filectx(f0).data(), wctx.filectx(f0).flags())
            wctx[f0].remove()
        progress.increment(item=f)

    # get in parallel.
    threadsafe = repo.ui.configbool(
        b'experimental', b'worker.wdir-get-thread-safe'
    )
    prog = worker.worker(
        repo.ui,
        cost,
        batchget,
        (repo, mctx, wctx, wantfiledata),
        actions[mergestatemod.ACTION_GET],
        threadsafe=threadsafe,
        hasretval=True,
    )
    getfiledata = {}
    for final, res in prog:
        if final:
            getfiledata = res
        else:
            i, item = res
            progress.increment(step=i, item=item)
    updated = len(actions[mergestatemod.ACTION_GET])

    if [a for a in actions[mergestatemod.ACTION_GET] if a[0] == b'.hgsubstate']:
        subrepoutil.submerge(repo, wctx, mctx, wctx, overwrite, labels)

    # forget (manifest only, just log it) (must come first)
    for f, args, msg in actions[mergestatemod.ACTION_FORGET]:
        repo.ui.debug(b" %s: %s -> f\n" % (f, msg))
        progress.increment(item=f)

    # re-add (manifest only, just log it)
    for f, args, msg in actions[mergestatemod.ACTION_ADD]:
        repo.ui.debug(b" %s: %s -> a\n" % (f, msg))
        progress.increment(item=f)

    # re-add/mark as modified (manifest only, just log it)
    for f, args, msg in actions[mergestatemod.ACTION_ADD_MODIFIED]:
        repo.ui.debug(b" %s: %s -> am\n" % (f, msg))
        progress.increment(item=f)

    # keep (noop, just log it)
    for f, args, msg in actions[mergestatemod.ACTION_KEEP]:
        repo.ui.debug(b" %s: %s -> k\n" % (f, msg))
        # no progress

    # directory rename, move local
    for f, args, msg in actions[mergestatemod.ACTION_DIR_RENAME_MOVE_LOCAL]:
        repo.ui.debug(b" %s: %s -> dm\n" % (f, msg))
        progress.increment(item=f)
        f0, flags = args
        repo.ui.note(_(b"moving %s to %s\n") % (f0, f))
        wctx[f].audit()
        wctx[f].write(wctx.filectx(f0).data(), flags)
        wctx[f0].remove()
        updated += 1

    # local directory rename, get
    for f, args, msg in actions[mergestatemod.ACTION_LOCAL_DIR_RENAME_GET]:
        repo.ui.debug(b" %s: %s -> dg\n" % (f, msg))
        progress.increment(item=f)
        f0, flags = args
        repo.ui.note(_(b"getting %s to %s\n") % (f0, f))
        wctx[f].write(mctx.filectx(f0).data(), flags)
        updated += 1

    # exec
    for f, args, msg in actions[mergestatemod.ACTION_EXEC]:
        repo.ui.debug(b" %s: %s -> e\n" % (f, msg))
        progress.increment(item=f)
        (flags,) = args
        wctx[f].audit()
        wctx[f].setflags(b'l' in flags, b'x' in flags)
        updated += 1

    # the ordering is important here -- ms.mergedriver will raise if the merge
    # driver has changed, and we want to be able to bypass it when overwrite is
    # True
    usemergedriver = not overwrite and mergeactions and ms.mergedriver

    if usemergedriver:
        if wctx.isinmemory():
            raise error.InMemoryMergeConflictsError(
                b"in-memory merge does not support mergedriver"
            )
        ms.commit()
        proceed = driverpreprocess(repo, ms, wctx, labels=labels)
        # the driver might leave some files unresolved
        unresolvedf = set(ms.unresolved())
        if not proceed:
            # XXX setting unresolved to at least 1 is a hack to make sure we
            # error out
            return updateresult(
                updated, merged, removed, max(len(unresolvedf), 1)
            )
        newactions = []
        for f, args, msg in mergeactions:
            if f in unresolvedf:
                newactions.append((f, args, msg))
        mergeactions = newactions

    try:
        # premerge
        tocomplete = []
        for f, args, msg in mergeactions:
            repo.ui.debug(b" %s: %s -> m (premerge)\n" % (f, msg))
            progress.increment(item=f)
            if f == b'.hgsubstate':  # subrepo states need updating
                subrepoutil.submerge(
                    repo, wctx, mctx, wctx.ancestor(mctx), overwrite, labels
                )
                continue
            wctx[f].audit()
            complete, r = ms.preresolve(f, wctx)
            if not complete:
                numupdates += 1
                tocomplete.append((f, args, msg))

        # merge
        for f, args, msg in tocomplete:
            repo.ui.debug(b" %s: %s -> m (merge)\n" % (f, msg))
            progress.increment(item=f, total=numupdates)
            ms.resolve(f, wctx)

    finally:
        ms.commit()

    unresolved = ms.unresolvedcount()

    if (
        usemergedriver
        and not unresolved
        and ms.mdstate() != mergestatemod.MERGE_DRIVER_STATE_SUCCESS
    ):
        if not driverconclude(repo, ms, wctx, labels=labels):
            # XXX setting unresolved to at least 1 is a hack to make sure we
            # error out
            unresolved = max(unresolved, 1)

        ms.commit()

    msupdated, msmerged, msremoved = ms.counts()
    updated += msupdated
    merged += msmerged
    removed += msremoved

    extraactions = ms.actions()
    if extraactions:
        mfiles = {a[0] for a in actions[mergestatemod.ACTION_MERGE]}
        for k, acts in pycompat.iteritems(extraactions):
            actions[k].extend(acts)
            if k == mergestatemod.ACTION_GET and wantfiledata:
                # no filedata until mergestate is updated to provide it
                for a in acts:
                    getfiledata[a[0]] = None
            # Remove these files from actions[ACTION_MERGE] as well. This is
            # important because in recordupdates, files in actions[ACTION_MERGE]
            # are processed after files in other actions, and the merge driver
            # might add files to those actions via extraactions above. This can
            # lead to a file being recorded twice, with poor results. This is
            # especially problematic for actions[ACTION_REMOVE] (currently only
            # possible with the merge driver in the initial merge process;
            # interrupted merges don't go through this flow).
            #
            # The real fix here is to have indexes by both file and action so
            # that when the action for a file is changed it is automatically
            # reflected in the other action lists. But that involves a more
            # complex data structure, so this will do for now.
            #
            # We don't need to do the same operation for 'dc' and 'cd' because
            # those lists aren't consulted again.
            mfiles.difference_update(a[0] for a in acts)

        actions[mergestatemod.ACTION_MERGE] = [
            a for a in actions[mergestatemod.ACTION_MERGE] if a[0] in mfiles
        ]

    progress.complete()
    assert len(getfiledata) == (
        len(actions[mergestatemod.ACTION_GET]) if wantfiledata else 0
    )
    return updateresult(updated, merged, removed, unresolved), getfiledata


UPDATECHECK_ABORT = b'abort'  # handled at higher layers
UPDATECHECK_NONE = b'none'
UPDATECHECK_LINEAR = b'linear'
UPDATECHECK_NO_CONFLICT = b'noconflict'


def update(
    repo,
    node,
    branchmerge,
    force,
    ancestor=None,
    mergeancestor=False,
    labels=None,
    matcher=None,
    mergeforce=False,
    updatedirstate=True,
    updatecheck=None,
    wc=None,
):
    """
    Perform a merge between the working directory and the given node

    node = the node to update to
    branchmerge = whether to merge between branches
    force = whether to force branch merging or file overwriting
    matcher = a matcher to filter file lists (dirstate not updated)
    mergeancestor = whether it is merging with an ancestor. If true,
      we should accept the incoming changes for any prompts that occur.
      If false, merging with an ancestor (fast-forward) is only allowed
      between different named branches. This flag is used by rebase extension
      as a temporary fix and should be avoided in general.
    labels = labels to use for base, local and other
    mergeforce = whether the merge was run with 'merge --force' (deprecated): if
      this is True, then 'force' should be True as well.

    The table below shows all the behaviors of the update command given the
    -c/--check and -C/--clean or no options, whether the working directory is
    dirty, whether a revision is specified, and the relationship of the parent
    rev to the target rev (linear or not). Match from top first. The -n
    option doesn't exist on the command line, but represents the
    experimental.updatecheck=noconflict option.

    This logic is tested by test-update-branches.t.

    -c  -C  -n  -m  dirty  rev  linear  |  result
     y   y   *   *    *     *     *     |    (1)
     y   *   y   *    *     *     *     |    (1)
     y   *   *   y    *     *     *     |    (1)
     *   y   y   *    *     *     *     |    (1)
     *   y   *   y    *     *     *     |    (1)
     *   *   y   y    *     *     *     |    (1)
     *   *   *   *    *     n     n     |     x
     *   *   *   *    n     *     *     |    ok
     n   n   n   n    y     *     y     |   merge
     n   n   n   n    y     y     n     |    (2)
     n   n   n   y    y     *     *     |   merge
     n   n   y   n    y     *     *     |  merge if no conflict
     n   y   n   n    y     *     *     |  discard
     y   n   n   n    y     *     *     |    (3)

    x = can't happen
    * = don't-care
    1 = incompatible options (checked in commands.py)
    2 = abort: uncommitted changes (commit or update --clean to discard changes)
    3 = abort: uncommitted changes (checked in commands.py)

    The merge is performed inside ``wc``, a workingctx-like objects. It defaults
    to repo[None] if None is passed.

    Return the same tuple as applyupdates().
    """
    # Avoid cycle.
    from . import sparse

    # This function used to find the default destination if node was None, but
    # that's now in destutil.py.
    assert node is not None
    if not branchmerge and not force:
        # TODO: remove the default once all callers that pass branchmerge=False
        # and force=False pass a value for updatecheck. We may want to allow
        # updatecheck='abort' to better suppport some of these callers.
        if updatecheck is None:
            updatecheck = UPDATECHECK_LINEAR
        if updatecheck not in (
            UPDATECHECK_NONE,
            UPDATECHECK_LINEAR,
            UPDATECHECK_NO_CONFLICT,
        ):
            raise ValueError(
                r'Invalid updatecheck %r (can accept %r)'
                % (
                    updatecheck,
                    (
                        UPDATECHECK_NONE,
                        UPDATECHECK_LINEAR,
                        UPDATECHECK_NO_CONFLICT,
                    ),
                )
            )
    with repo.wlock():
        if wc is None:
            wc = repo[None]
        pl = wc.parents()
        p1 = pl[0]
        p2 = repo[node]
        if ancestor is not None:
            pas = [repo[ancestor]]
        else:
            if repo.ui.configlist(b'merge', b'preferancestor') == [b'*']:
                cahs = repo.changelog.commonancestorsheads(p1.node(), p2.node())
                pas = [repo[anc] for anc in (sorted(cahs) or [nullid])]
            else:
                pas = [p1.ancestor(p2, warn=branchmerge)]

        fp1, fp2, xp1, xp2 = p1.node(), p2.node(), bytes(p1), bytes(p2)

        overwrite = force and not branchmerge
        ### check phase
        if not overwrite:
            if len(pl) > 1:
                raise error.Abort(_(b"outstanding uncommitted merge"))
            ms = mergestatemod.mergestate.read(repo)
            if list(ms.unresolved()):
                raise error.Abort(
                    _(b"outstanding merge conflicts"),
                    hint=_(b"use 'hg resolve' to resolve"),
                )
        if branchmerge:
            if pas == [p2]:
                raise error.Abort(
                    _(
                        b"merging with a working directory ancestor"
                        b" has no effect"
                    )
                )
            elif pas == [p1]:
                if not mergeancestor and wc.branch() == p2.branch():
                    raise error.Abort(
                        _(b"nothing to merge"),
                        hint=_(b"use 'hg update' or check 'hg heads'"),
                    )
            if not force and (wc.files() or wc.deleted()):
                raise error.Abort(
                    _(b"uncommitted changes"),
                    hint=_(b"use 'hg status' to list changes"),
                )
            if not wc.isinmemory():
                for s in sorted(wc.substate):
                    wc.sub(s).bailifchanged()

        elif not overwrite:
            if p1 == p2:  # no-op update
                # call the hooks and exit early
                repo.hook(b'preupdate', throw=True, parent1=xp2, parent2=b'')
                repo.hook(b'update', parent1=xp2, parent2=b'', error=0)
                return updateresult(0, 0, 0, 0)

            if updatecheck == UPDATECHECK_LINEAR and pas not in (
                [p1],
                [p2],
            ):  # nonlinear
                dirty = wc.dirty(missing=True)
                if dirty:
                    # Branching is a bit strange to ensure we do the minimal
                    # amount of call to obsutil.foreground.
                    foreground = obsutil.foreground(repo, [p1.node()])
                    # note: the <node> variable contains a random identifier
                    if repo[node].node() in foreground:
                        pass  # allow updating to successors
                    else:
                        msg = _(b"uncommitted changes")
                        hint = _(b"commit or update --clean to discard changes")
                        raise error.UpdateAbort(msg, hint=hint)
                else:
                    # Allow jumping branches if clean and specific rev given
                    pass

        if overwrite:
            pas = [wc]
        elif not branchmerge:
            pas = [p1]

        # deprecated config: merge.followcopies
        followcopies = repo.ui.configbool(b'merge', b'followcopies')
        if overwrite:
            followcopies = False
        elif not pas[0]:
            followcopies = False
        if not branchmerge and not wc.dirty(missing=True):
            followcopies = False

        ### calculate phase
        actionbyfile, diverge, renamedelete = calculateupdates(
            repo,
            wc,
            p2,
            pas,
            branchmerge,
            force,
            mergeancestor,
            followcopies,
            matcher=matcher,
            mergeforce=mergeforce,
        )

        if updatecheck == UPDATECHECK_NO_CONFLICT:
            for f, (m, args, msg) in pycompat.iteritems(actionbyfile):
                if m not in (
                    mergestatemod.ACTION_GET,
                    mergestatemod.ACTION_KEEP,
                    mergestatemod.ACTION_EXEC,
                    mergestatemod.ACTION_REMOVE,
                    mergestatemod.ACTION_PATH_CONFLICT_RESOLVE,
                    mergestatemod.ACTION_GET_OTHER_AND_STORE,
                ):
                    msg = _(b"conflicting changes")
                    hint = _(b"commit or update --clean to discard changes")
                    raise error.Abort(msg, hint=hint)

        # Prompt and create actions. Most of this is in the resolve phase
        # already, but we can't handle .hgsubstate in filemerge or
        # subrepoutil.submerge yet so we have to keep prompting for it.
        if b'.hgsubstate' in actionbyfile:
            f = b'.hgsubstate'
            m, args, msg = actionbyfile[f]
            prompts = filemerge.partextras(labels)
            prompts[b'f'] = f
            if m == mergestatemod.ACTION_CHANGED_DELETED:
                if repo.ui.promptchoice(
                    _(
                        b"local%(l)s changed %(f)s which other%(o)s deleted\n"
                        b"use (c)hanged version or (d)elete?"
                        b"$$ &Changed $$ &Delete"
                    )
                    % prompts,
                    0,
                ):
                    actionbyfile[f] = (
                        mergestatemod.ACTION_REMOVE,
                        None,
                        b'prompt delete',
                    )
                elif f in p1:
                    actionbyfile[f] = (
                        mergestatemod.ACTION_ADD_MODIFIED,
                        None,
                        b'prompt keep',
                    )
                else:
                    actionbyfile[f] = (
                        mergestatemod.ACTION_ADD,
                        None,
                        b'prompt keep',
                    )
            elif m == mergestatemod.ACTION_DELETED_CHANGED:
                f1, f2, fa, move, anc = args
                flags = p2[f2].flags()
                if (
                    repo.ui.promptchoice(
                        _(
                            b"other%(o)s changed %(f)s which local%(l)s deleted\n"
                            b"use (c)hanged version or leave (d)eleted?"
                            b"$$ &Changed $$ &Deleted"
                        )
                        % prompts,
                        0,
                    )
                    == 0
                ):
                    actionbyfile[f] = (
                        mergestatemod.ACTION_GET,
                        (flags, False),
                        b'prompt recreating',
                    )
                else:
                    del actionbyfile[f]

        # Convert to dictionary-of-lists format
        actions = emptyactions()
        for f, (m, args, msg) in pycompat.iteritems(actionbyfile):
            if m not in actions:
                actions[m] = []
            actions[m].append((f, args, msg))

        # ACTION_GET_OTHER_AND_STORE is a mergestatemod.ACTION_GET + store in mergestate
        for e in actions[mergestatemod.ACTION_GET_OTHER_AND_STORE]:
            actions[mergestatemod.ACTION_GET].append(e)

        if not util.fscasesensitive(repo.path):
            # check collision between files only in p2 for clean update
            if not branchmerge and (
                force or not wc.dirty(missing=True, branch=False)
            ):
                _checkcollision(repo, p2.manifest(), None)
            else:
                _checkcollision(repo, wc.manifest(), actions)

        # divergent renames
        for f, fl in sorted(pycompat.iteritems(diverge)):
            repo.ui.warn(
                _(
                    b"note: possible conflict - %s was renamed "
                    b"multiple times to:\n"
                )
                % f
            )
            for nf in sorted(fl):
                repo.ui.warn(b" %s\n" % nf)

        # rename and delete
        for f, fl in sorted(pycompat.iteritems(renamedelete)):
            repo.ui.warn(
                _(
                    b"note: possible conflict - %s was deleted "
                    b"and renamed to:\n"
                )
                % f
            )
            for nf in sorted(fl):
                repo.ui.warn(b" %s\n" % nf)

        ### apply phase
        if not branchmerge:  # just jump to the new rev
            fp1, fp2, xp1, xp2 = fp2, nullid, xp2, b''
        # If we're doing a partial update, we need to skip updating
        # the dirstate.
        always = matcher is None or matcher.always()
        updatedirstate = updatedirstate and always and not wc.isinmemory()
        if updatedirstate:
            repo.hook(b'preupdate', throw=True, parent1=xp1, parent2=xp2)
            # note that we're in the middle of an update
            repo.vfs.write(b'updatestate', p2.hex())

        # Advertise fsmonitor when its presence could be useful.
        #
        # We only advertise when performing an update from an empty working
        # directory. This typically only occurs during initial clone.
        #
        # We give users a mechanism to disable the warning in case it is
        # annoying.
        #
        # We only allow on Linux and MacOS because that's where fsmonitor is
        # considered stable.
        fsmonitorwarning = repo.ui.configbool(b'fsmonitor', b'warn_when_unused')
        fsmonitorthreshold = repo.ui.configint(
            b'fsmonitor', b'warn_update_file_count'
        )
        try:
            # avoid cycle: extensions -> cmdutil -> merge
            from . import extensions

            extensions.find(b'fsmonitor')
            fsmonitorenabled = repo.ui.config(b'fsmonitor', b'mode') != b'off'
            # We intentionally don't look at whether fsmonitor has disabled
            # itself because a) fsmonitor may have already printed a warning
            # b) we only care about the config state here.
        except KeyError:
            fsmonitorenabled = False

        if (
            fsmonitorwarning
            and not fsmonitorenabled
            and p1.node() == nullid
            and len(actions[mergestatemod.ACTION_GET]) >= fsmonitorthreshold
            and pycompat.sysplatform.startswith((b'linux', b'darwin'))
        ):
            repo.ui.warn(
                _(
                    b'(warning: large working directory being used without '
                    b'fsmonitor enabled; enable fsmonitor to improve performance; '
                    b'see "hg help -e fsmonitor")\n'
                )
            )

        wantfiledata = updatedirstate and not branchmerge
        stats, getfiledata = applyupdates(
            repo, actions, wc, p2, overwrite, wantfiledata, labels=labels
        )

        if updatedirstate:
            with repo.dirstate.parentchange():
                repo.setparents(fp1, fp2)
                mergestatemod.recordupdates(
                    repo, actions, branchmerge, getfiledata
                )
                # update completed, clear state
                util.unlink(repo.vfs.join(b'updatestate'))

                if not branchmerge:
                    repo.dirstate.setbranch(p2.branch())

    # If we're updating to a location, clean up any stale temporary includes
    # (ex: this happens during hg rebase --abort).
    if not branchmerge:
        sparse.prunetemporaryincludes(repo)

    if updatedirstate:
        repo.hook(
            b'update', parent1=xp1, parent2=xp2, error=stats.unresolvedcount
        )
    return stats


def merge(ctx, labels=None, force=False, wc=None):
    """Merge another topological branch into the working copy.

    force = whether the merge was run with 'merge --force' (deprecated)
    """

    return update(
        ctx.repo(),
        ctx.rev(),
        labels=labels,
        branchmerge=True,
        force=force,
        mergeforce=force,
        wc=wc,
    )


def clean_update(ctx, wc=None):
    """Do a clean update to the given commit.

    This involves updating to the commit and discarding any changes in the
    working copy.
    """
    return update(ctx.repo(), ctx.rev(), branchmerge=False, force=True, wc=wc)


def revert_to(ctx, matcher=None, wc=None):
    """Revert the working copy to the given commit.

    The working copy will keep its current parent(s) but its content will
    be the same as in the given commit.
    """

    return update(
        ctx.repo(),
        ctx.rev(),
        branchmerge=False,
        force=True,
        updatedirstate=False,
        matcher=matcher,
        wc=wc,
    )


def graft(
    repo,
    ctx,
    base=None,
    labels=None,
    keepparent=False,
    keepconflictparent=False,
    wctx=None,
):
    """Do a graft-like merge.

    This is a merge where the merge ancestor is chosen such that one
    or more changesets are grafted onto the current changeset. In
    addition to the merge, this fixes up the dirstate to include only
    a single parent (if keepparent is False) and tries to duplicate any
    renames/copies appropriately.

    ctx - changeset to rebase
    base - merge base, or ctx.p1() if not specified
    labels - merge labels eg ['local', 'graft']
    keepparent - keep second parent if any
    keepconflictparent - if unresolved, keep parent used for the merge

    """
    # If we're grafting a descendant onto an ancestor, be sure to pass
    # mergeancestor=True to update. This does two things: 1) allows the merge if
    # the destination is the same as the parent of the ctx (so we can use graft
    # to copy commits), and 2) informs update that the incoming changes are
    # newer than the destination so it doesn't prompt about "remote changed foo
    # which local deleted".
    # We also pass mergeancestor=True when base is the same revision as p1. 2)
    # doesn't matter as there can't possibly be conflicts, but 1) is necessary.
    wctx = wctx or repo[None]
    pctx = wctx.p1()
    base = base or ctx.p1()
    mergeancestor = (
        repo.changelog.isancestor(pctx.node(), ctx.node())
        or pctx.rev() == base.rev()
    )

    stats = update(
        repo,
        ctx.node(),
        True,
        True,
        base.node(),
        mergeancestor=mergeancestor,
        labels=labels,
        wc=wctx,
    )

    if keepconflictparent and stats.unresolvedcount:
        pother = ctx.node()
    else:
        pother = nullid
        parents = ctx.parents()
        if keepparent and len(parents) == 2 and base in parents:
            parents.remove(base)
            pother = parents[0].node()
    # Never set both parents equal to each other
    if pother == pctx.node():
        pother = nullid

    if wctx.isinmemory():
        wctx.setparents(pctx.node(), pother)
        # fix up dirstate for copies and renames
        copies.graftcopies(wctx, ctx, base)
    else:
        with repo.dirstate.parentchange():
            repo.setparents(pctx.node(), pother)
            repo.dirstate.write(repo.currenttransaction())
            # fix up dirstate for copies and renames
            copies.graftcopies(wctx, ctx, base)
    return stats


def purge(
    repo,
    matcher,
    unknown=True,
    ignored=False,
    removeemptydirs=True,
    removefiles=True,
    abortonerror=False,
    noop=False,
):
    """Purge the working directory of untracked files.

    ``matcher`` is a matcher configured to scan the working directory -
    potentially a subset.

    ``unknown`` controls whether unknown files should be purged.

    ``ignored`` controls whether ignored files should be purged.

    ``removeemptydirs`` controls whether empty directories should be removed.

    ``removefiles`` controls whether files are removed.

    ``abortonerror`` causes an exception to be raised if an error occurs
    deleting a file or directory.

    ``noop`` controls whether to actually remove files. If not defined, actions
    will be taken.

    Returns an iterable of relative paths in the working directory that were
    or would be removed.
    """

    def remove(removefn, path):
        try:
            removefn(path)
        except OSError:
            m = _(b'%s cannot be removed') % path
            if abortonerror:
                raise error.Abort(m)
            else:
                repo.ui.warn(_(b'warning: %s\n') % m)

    # There's no API to copy a matcher. So mutate the passed matcher and
    # restore it when we're done.
    oldtraversedir = matcher.traversedir

    res = []

    try:
        if removeemptydirs:
            directories = []
            matcher.traversedir = directories.append

        status = repo.status(match=matcher, ignored=ignored, unknown=unknown)

        if removefiles:
            for f in sorted(status.unknown + status.ignored):
                if not noop:
                    repo.ui.note(_(b'removing file %s\n') % f)
                    remove(repo.wvfs.unlink, f)
                res.append(f)

        if removeemptydirs:
            for f in sorted(directories, reverse=True):
                if matcher(f) and not repo.wvfs.listdir(f):
                    if not noop:
                        repo.ui.note(_(b'removing directory %s\n') % f)
                        remove(repo.wvfs.rmdir, f)
                    res.append(f)

        return res

    finally:
        matcher.traversedir = oldtraversedir
