# commit.py - fonction to perform commit
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import errno
import weakref

from .i18n import _
from .node import (
    hex,
    nullrev,
)

from . import (
    metadata,
    phases,
    scmutil,
    subrepoutil,
)


def commitctx(repo, ctx, error=False, origctx=None):
    """Add a new revision to the target repository.
    Revision information is passed via the context argument.

    ctx.files() should list all files involved in this commit, i.e.
    modified/added/removed files. On merge, it may be wider than the
    ctx.files() to be committed, since any file nodes derived directly
    from p1 or p2 are excluded from the committed ctx.files().

    origctx is for convert to work around the problem that bug
    fixes to the files list in changesets change hashes. For
    convert to be the identity, it can pass an origctx and this
    function will use the same files list when it makes sense to
    do so.
    """
    repo = repo.unfiltered()

    p1, p2 = ctx.p1(), ctx.p2()
    user = ctx.user()

    if repo.filecopiesmode == b'changeset-sidedata':
        writechangesetcopy = True
        writefilecopymeta = True
        writecopiesto = None
    else:
        writecopiesto = repo.ui.config(b'experimental', b'copies.write-to')
        writefilecopymeta = writecopiesto != b'changeset-only'
        writechangesetcopy = writecopiesto in (
            b'changeset-only',
            b'compatibility',
        )
    p1copies, p2copies = None, None
    if writechangesetcopy:
        p1copies = ctx.p1copies()
        p2copies = ctx.p2copies()
    filesadded, filesremoved = None, None
    with repo.lock(), repo.transaction(b"commit") as tr:
        trp = weakref.proxy(tr)

        if ctx.manifestnode():
            # reuse an existing manifest revision
            repo.ui.debug(b'reusing known manifest\n')
            mn = ctx.manifestnode()
            files = ctx.files()
            if writechangesetcopy:
                filesadded = ctx.filesadded()
                filesremoved = ctx.filesremoved()
        elif not ctx.files():
            repo.ui.debug(b'reusing manifest from p1 (no file change)\n')
            mn = p1.manifestnode()
            files = []
        else:
            m1ctx = p1.manifestctx()
            m2ctx = p2.manifestctx()
            mctx = m1ctx.copy()

            m = mctx.read()
            m1 = m1ctx.read()
            m2 = m2ctx.read()

            # check in files
            added = []
            filesadded = []
            removed = list(ctx.removed())
            touched = []
            linkrev = len(repo)
            repo.ui.note(_(b"committing files:\n"))
            uipathfn = scmutil.getuipathfn(repo)
            for f in sorted(ctx.modified() + ctx.added()):
                repo.ui.note(uipathfn(f) + b"\n")
                try:
                    fctx = ctx[f]
                    if fctx is None:
                        removed.append(f)
                    else:
                        added.append(f)
                        m[f], is_touched = repo._filecommit(
                            fctx, m1, m2, linkrev, trp, writefilecopymeta,
                        )
                        if is_touched:
                            touched.append(f)
                            if writechangesetcopy and is_touched == 'added':
                                filesadded.append(f)
                        m.setflag(f, fctx.flags())
                except OSError:
                    repo.ui.warn(_(b"trouble committing %s!\n") % uipathfn(f))
                    raise
                except IOError as inst:
                    errcode = getattr(inst, 'errno', errno.ENOENT)
                    if error or errcode and errcode != errno.ENOENT:
                        repo.ui.warn(
                            _(b"trouble committing %s!\n") % uipathfn(f)
                        )
                    raise

            # update manifest
            removed = [f for f in removed if f in m1 or f in m2]
            drop = sorted([f for f in removed if f in m])
            for f in drop:
                del m[f]
            if p2.rev() != nullrev:
                rf = metadata.get_removal_filter(ctx, (p1, p2, m1, m2))
                removed = [f for f in removed if not rf(f)]

            touched.extend(removed)

            if writechangesetcopy:
                filesremoved = removed

            files = touched
            md = None
            if not files:
                # if no "files" actually changed in terms of the changelog,
                # try hard to detect unmodified manifest entry so that the
                # exact same commit can be reproduced later on convert.
                md = m1.diff(m, scmutil.matchfiles(repo, ctx.files()))
            if not files and md:
                repo.ui.debug(
                    b'not reusing manifest (no file change in '
                    b'changelog, but manifest differs)\n'
                )
            if files or md:
                repo.ui.note(_(b"committing manifest\n"))
                # we're using narrowmatch here since it's already applied at
                # other stages (such as dirstate.walk), so we're already
                # ignoring things outside of narrowspec in most cases. The
                # one case where we might have files outside the narrowspec
                # at this point is merges, and we already error out in the
                # case where the merge has files outside of the narrowspec,
                # so this is safe.
                mn = mctx.write(
                    trp,
                    linkrev,
                    p1.manifestnode(),
                    p2.manifestnode(),
                    added,
                    drop,
                    match=repo.narrowmatch(),
                )
            else:
                repo.ui.debug(
                    b'reusing manifest from p1 (listed files '
                    b'actually unchanged)\n'
                )
                mn = p1.manifestnode()

        if writecopiesto == b'changeset-only':
            # If writing only to changeset extras, use None to indicate that
            # no entry should be written. If writing to both, write an empty
            # entry to prevent the reader from falling back to reading
            # filelogs.
            p1copies = p1copies or None
            p2copies = p2copies or None
            filesadded = filesadded or None
            filesremoved = filesremoved or None

        if origctx and origctx.manifestnode() == mn:
            files = origctx.files()

        # update changelog
        repo.ui.note(_(b"committing changelog\n"))
        repo.changelog.delayupdate(tr)
        n = repo.changelog.add(
            mn,
            files,
            ctx.description(),
            trp,
            p1.node(),
            p2.node(),
            user,
            ctx.date(),
            ctx.extra().copy(),
            p1copies,
            p2copies,
            filesadded,
            filesremoved,
        )
        xp1, xp2 = p1.hex(), p2 and p2.hex() or b''
        repo.hook(
            b'pretxncommit', throw=True, node=hex(n), parent1=xp1, parent2=xp2,
        )
        # set the new commit is proper phase
        targetphase = subrepoutil.newcommitphase(repo.ui, ctx)
        if targetphase:
            # retract boundary do not alter parent changeset.
            # if a parent have higher the resulting phase will
            # be compliant anyway
            #
            # if minimal phase was 0 we don't need to retract anything
            phases.registernew(repo, tr, targetphase, [n])
        return n
