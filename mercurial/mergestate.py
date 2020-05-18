from __future__ import absolute_import

import errno
import shutil
import struct

from .i18n import _
from .node import (
    bin,
    hex,
    nullhex,
    nullid,
)
from .pycompat import delattr
from . import (
    error,
    filemerge,
    pycompat,
    util,
)
from .utils import hashutil

_pack = struct.pack
_unpack = struct.unpack


def _droponode(data):
    # used for compatibility for v1
    bits = data.split(b'\0')
    bits = bits[:-2] + bits[-1:]
    return b'\0'.join(bits)


# Merge state record types. See ``mergestate`` docs for more.
RECORD_LOCAL = b'L'
RECORD_OTHER = b'O'
RECORD_MERGED = b'F'
RECORD_CHANGEDELETE_CONFLICT = b'C'
RECORD_MERGE_DRIVER_MERGE = b'D'
RECORD_PATH_CONFLICT = b'P'
RECORD_MERGE_DRIVER_STATE = b'm'
RECORD_FILE_VALUES = b'f'
RECORD_LABELS = b'l'
RECORD_OVERRIDE = b't'
RECORD_UNSUPPORTED_MANDATORY = b'X'
RECORD_UNSUPPORTED_ADVISORY = b'x'
RECORD_RESOLVED_OTHER = b'R'

MERGE_DRIVER_STATE_UNMARKED = b'u'
MERGE_DRIVER_STATE_MARKED = b'm'
MERGE_DRIVER_STATE_SUCCESS = b's'

MERGE_RECORD_UNRESOLVED = b'u'
MERGE_RECORD_RESOLVED = b'r'
MERGE_RECORD_UNRESOLVED_PATH = b'pu'
MERGE_RECORD_RESOLVED_PATH = b'pr'
MERGE_RECORD_DRIVER_RESOLVED = b'd'
# represents that the file was automatically merged in favor
# of other version. This info is used on commit.
MERGE_RECORD_MERGED_OTHER = b'o'

ACTION_FORGET = b'f'
ACTION_REMOVE = b'r'
ACTION_ADD = b'a'
ACTION_GET = b'g'
ACTION_PATH_CONFLICT = b'p'
ACTION_PATH_CONFLICT_RESOLVE = b'pr'
ACTION_ADD_MODIFIED = b'am'
ACTION_CREATED = b'c'
ACTION_DELETED_CHANGED = b'dc'
ACTION_CHANGED_DELETED = b'cd'
ACTION_MERGE = b'm'
ACTION_LOCAL_DIR_RENAME_GET = b'dg'
ACTION_DIR_RENAME_MOVE_LOCAL = b'dm'
ACTION_KEEP = b'k'
ACTION_EXEC = b'e'
ACTION_CREATED_MERGE = b'cm'
# GET the other/remote side and store this info in mergestate
ACTION_GET_OTHER_AND_STORE = b'gs'


class mergestate(object):
    '''track 3-way merge state of individual files

    The merge state is stored on disk when needed. Two files are used: one with
    an old format (version 1), and one with a new format (version 2). Version 2
    stores a superset of the data in version 1, including new kinds of records
    in the future. For more about the new format, see the documentation for
    `_readrecordsv2`.

    Each record can contain arbitrary content, and has an associated type. This
    `type` should be a letter. If `type` is uppercase, the record is mandatory:
    versions of Mercurial that don't support it should abort. If `type` is
    lowercase, the record can be safely ignored.

    Currently known records:

    L: the node of the "local" part of the merge (hexified version)
    O: the node of the "other" part of the merge (hexified version)
    F: a file to be merged entry
    C: a change/delete or delete/change conflict
    D: a file that the external merge driver will merge internally
       (experimental)
    P: a path conflict (file vs directory)
    m: the external merge driver defined for this merge plus its run state
       (experimental)
    f: a (filename, dictionary) tuple of optional values for a given file
    X: unsupported mandatory record type (used in tests)
    x: unsupported advisory record type (used in tests)
    l: the labels for the parts of the merge.

    Merge driver run states (experimental):
    u: driver-resolved files unmarked -- needs to be run next time we're about
       to resolve or commit
    m: driver-resolved files marked -- only needs to be run before commit
    s: success/skipped -- does not need to be run any more

    Merge record states (stored in self._state, indexed by filename):
    u: unresolved conflict
    r: resolved conflict
    pu: unresolved path conflict (file conflicts with directory)
    pr: resolved path conflict
    d: driver-resolved conflict

    The resolve command transitions between 'u' and 'r' for conflicts and
    'pu' and 'pr' for path conflicts.
    '''

    statepathv1 = b'merge/state'
    statepathv2 = b'merge/state2'

    @staticmethod
    def clean(repo, node=None, other=None, labels=None):
        """Initialize a brand new merge state, removing any existing state on
        disk."""
        ms = mergestate(repo)
        ms.reset(node, other, labels)
        return ms

    @staticmethod
    def read(repo):
        """Initialize the merge state, reading it from disk."""
        ms = mergestate(repo)
        ms._read()
        return ms

    def __init__(self, repo):
        """Initialize the merge state.

        Do not use this directly! Instead call read() or clean()."""
        self._repo = repo
        self._dirty = False
        self._labels = None

    def reset(self, node=None, other=None, labels=None):
        self._state = {}
        self._stateextras = {}
        self._local = None
        self._other = None
        self._labels = labels
        for var in ('localctx', 'otherctx'):
            if var in vars(self):
                delattr(self, var)
        if node:
            self._local = node
            self._other = other
        self._readmergedriver = None
        if self.mergedriver:
            self._mdstate = MERGE_DRIVER_STATE_SUCCESS
        else:
            self._mdstate = MERGE_DRIVER_STATE_UNMARKED
        shutil.rmtree(self._repo.vfs.join(b'merge'), True)
        self._results = {}
        self._dirty = False

    def _read(self):
        """Analyse each record content to restore a serialized state from disk

        This function process "record" entry produced by the de-serialization
        of on disk file.
        """
        self._state = {}
        self._stateextras = {}
        self._local = None
        self._other = None
        for var in ('localctx', 'otherctx'):
            if var in vars(self):
                delattr(self, var)
        self._readmergedriver = None
        self._mdstate = MERGE_DRIVER_STATE_SUCCESS
        unsupported = set()
        records = self._readrecords()
        for rtype, record in records:
            if rtype == RECORD_LOCAL:
                self._local = bin(record)
            elif rtype == RECORD_OTHER:
                self._other = bin(record)
            elif rtype == RECORD_MERGE_DRIVER_STATE:
                bits = record.split(b'\0', 1)
                mdstate = bits[1]
                if len(mdstate) != 1 or mdstate not in (
                    MERGE_DRIVER_STATE_UNMARKED,
                    MERGE_DRIVER_STATE_MARKED,
                    MERGE_DRIVER_STATE_SUCCESS,
                ):
                    # the merge driver should be idempotent, so just rerun it
                    mdstate = MERGE_DRIVER_STATE_UNMARKED

                self._readmergedriver = bits[0]
                self._mdstate = mdstate
            elif rtype in (
                RECORD_MERGED,
                RECORD_CHANGEDELETE_CONFLICT,
                RECORD_PATH_CONFLICT,
                RECORD_MERGE_DRIVER_MERGE,
                RECORD_RESOLVED_OTHER,
            ):
                bits = record.split(b'\0')
                self._state[bits[0]] = bits[1:]
            elif rtype == RECORD_FILE_VALUES:
                filename, rawextras = record.split(b'\0', 1)
                extraparts = rawextras.split(b'\0')
                extras = {}
                i = 0
                while i < len(extraparts):
                    extras[extraparts[i]] = extraparts[i + 1]
                    i += 2

                self._stateextras[filename] = extras
            elif rtype == RECORD_LABELS:
                labels = record.split(b'\0', 2)
                self._labels = [l for l in labels if len(l) > 0]
            elif not rtype.islower():
                unsupported.add(rtype)
        self._results = {}
        self._dirty = False

        if unsupported:
            raise error.UnsupportedMergeRecords(unsupported)

    def _readrecords(self):
        """Read merge state from disk and return a list of record (TYPE, data)

        We read data from both v1 and v2 files and decide which one to use.

        V1 has been used by version prior to 2.9.1 and contains less data than
        v2. We read both versions and check if no data in v2 contradicts
        v1. If there is not contradiction we can safely assume that both v1
        and v2 were written at the same time and use the extract data in v2. If
        there is contradiction we ignore v2 content as we assume an old version
        of Mercurial has overwritten the mergestate file and left an old v2
        file around.

        returns list of record [(TYPE, data), ...]"""
        v1records = self._readrecordsv1()
        v2records = self._readrecordsv2()
        if self._v1v2match(v1records, v2records):
            return v2records
        else:
            # v1 file is newer than v2 file, use it
            # we have to infer the "other" changeset of the merge
            # we cannot do better than that with v1 of the format
            mctx = self._repo[None].parents()[-1]
            v1records.append((RECORD_OTHER, mctx.hex()))
            # add place holder "other" file node information
            # nobody is using it yet so we do no need to fetch the data
            # if mctx was wrong `mctx[bits[-2]]` may fails.
            for idx, r in enumerate(v1records):
                if r[0] == RECORD_MERGED:
                    bits = r[1].split(b'\0')
                    bits.insert(-2, b'')
                    v1records[idx] = (r[0], b'\0'.join(bits))
            return v1records

    def _v1v2match(self, v1records, v2records):
        oldv2 = set()  # old format version of v2 record
        for rec in v2records:
            if rec[0] == RECORD_LOCAL:
                oldv2.add(rec)
            elif rec[0] == RECORD_MERGED:
                # drop the onode data (not contained in v1)
                oldv2.add((RECORD_MERGED, _droponode(rec[1])))
        for rec in v1records:
            if rec not in oldv2:
                return False
        else:
            return True

    def _readrecordsv1(self):
        """read on disk merge state for version 1 file

        returns list of record [(TYPE, data), ...]

        Note: the "F" data from this file are one entry short
              (no "other file node" entry)
        """
        records = []
        try:
            f = self._repo.vfs(self.statepathv1)
            for i, l in enumerate(f):
                if i == 0:
                    records.append((RECORD_LOCAL, l[:-1]))
                else:
                    records.append((RECORD_MERGED, l[:-1]))
            f.close()
        except IOError as err:
            if err.errno != errno.ENOENT:
                raise
        return records

    def _readrecordsv2(self):
        """read on disk merge state for version 2 file

        This format is a list of arbitrary records of the form:

          [type][length][content]

        `type` is a single character, `length` is a 4 byte integer, and
        `content` is an arbitrary byte sequence of length `length`.

        Mercurial versions prior to 3.7 have a bug where if there are
        unsupported mandatory merge records, attempting to clear out the merge
        state with hg update --clean or similar aborts. The 't' record type
        works around that by writing out what those versions treat as an
        advisory record, but later versions interpret as special: the first
        character is the 'real' record type and everything onwards is the data.

        Returns list of records [(TYPE, data), ...]."""
        records = []
        try:
            f = self._repo.vfs(self.statepathv2)
            data = f.read()
            off = 0
            end = len(data)
            while off < end:
                rtype = data[off : off + 1]
                off += 1
                length = _unpack(b'>I', data[off : (off + 4)])[0]
                off += 4
                record = data[off : (off + length)]
                off += length
                if rtype == RECORD_OVERRIDE:
                    rtype, record = record[0:1], record[1:]
                records.append((rtype, record))
            f.close()
        except IOError as err:
            if err.errno != errno.ENOENT:
                raise
        return records

    @util.propertycache
    def mergedriver(self):
        # protect against the following:
        # - A configures a malicious merge driver in their hgrc, then
        #   pauses the merge
        # - A edits their hgrc to remove references to the merge driver
        # - A gives a copy of their entire repo, including .hg, to B
        # - B inspects .hgrc and finds it to be clean
        # - B then continues the merge and the malicious merge driver
        #  gets invoked
        configmergedriver = self._repo.ui.config(
            b'experimental', b'mergedriver'
        )
        if (
            self._readmergedriver is not None
            and self._readmergedriver != configmergedriver
        ):
            raise error.ConfigError(
                _(b"merge driver changed since merge started"),
                hint=_(b"revert merge driver change or abort merge"),
            )

        return configmergedriver

    @util.propertycache
    def local(self):
        if self._local is None:
            msg = b"local accessed but self._local isn't set"
            raise error.ProgrammingError(msg)
        return self._local

    @util.propertycache
    def localctx(self):
        return self._repo[self.local]

    @util.propertycache
    def other(self):
        if self._other is None:
            msg = b"other accessed but self._other isn't set"
            raise error.ProgrammingError(msg)
        return self._other

    @util.propertycache
    def otherctx(self):
        return self._repo[self.other]

    def active(self):
        """Whether mergestate is active.

        Returns True if there appears to be mergestate. This is a rough proxy
        for "is a merge in progress."
        """
        return bool(self._local) or bool(self._state)

    def commit(self):
        """Write current state on disk (if necessary)"""
        if self._dirty:
            records = self._makerecords()
            self._writerecords(records)
            self._dirty = False

    def _makerecords(self):
        records = []
        records.append((RECORD_LOCAL, hex(self._local)))
        records.append((RECORD_OTHER, hex(self._other)))
        if self.mergedriver:
            records.append(
                (
                    RECORD_MERGE_DRIVER_STATE,
                    b'\0'.join([self.mergedriver, self._mdstate]),
                )
            )
        # Write out state items. In all cases, the value of the state map entry
        # is written as the contents of the record. The record type depends on
        # the type of state that is stored, and capital-letter records are used
        # to prevent older versions of Mercurial that do not support the feature
        # from loading them.
        for filename, v in pycompat.iteritems(self._state):
            if v[0] == MERGE_RECORD_DRIVER_RESOLVED:
                # Driver-resolved merge. These are stored in 'D' records.
                records.append(
                    (RECORD_MERGE_DRIVER_MERGE, b'\0'.join([filename] + v))
                )
            elif v[0] in (
                MERGE_RECORD_UNRESOLVED_PATH,
                MERGE_RECORD_RESOLVED_PATH,
            ):
                # Path conflicts. These are stored in 'P' records.  The current
                # resolution state ('pu' or 'pr') is stored within the record.
                records.append(
                    (RECORD_PATH_CONFLICT, b'\0'.join([filename] + v))
                )
            elif v[0] == MERGE_RECORD_MERGED_OTHER:
                records.append(
                    (RECORD_RESOLVED_OTHER, b'\0'.join([filename] + v))
                )
            elif v[1] == nullhex or v[6] == nullhex:
                # Change/Delete or Delete/Change conflicts. These are stored in
                # 'C' records. v[1] is the local file, and is nullhex when the
                # file is deleted locally ('dc'). v[6] is the remote file, and
                # is nullhex when the file is deleted remotely ('cd').
                records.append(
                    (RECORD_CHANGEDELETE_CONFLICT, b'\0'.join([filename] + v))
                )
            else:
                # Normal files.  These are stored in 'F' records.
                records.append((RECORD_MERGED, b'\0'.join([filename] + v)))
        for filename, extras in sorted(pycompat.iteritems(self._stateextras)):
            rawextras = b'\0'.join(
                b'%s\0%s' % (k, v) for k, v in pycompat.iteritems(extras)
            )
            records.append(
                (RECORD_FILE_VALUES, b'%s\0%s' % (filename, rawextras))
            )
        if self._labels is not None:
            labels = b'\0'.join(self._labels)
            records.append((RECORD_LABELS, labels))
        return records

    def _writerecords(self, records):
        """Write current state on disk (both v1 and v2)"""
        self._writerecordsv1(records)
        self._writerecordsv2(records)

    def _writerecordsv1(self, records):
        """Write current state on disk in a version 1 file"""
        f = self._repo.vfs(self.statepathv1, b'wb')
        irecords = iter(records)
        lrecords = next(irecords)
        assert lrecords[0] == RECORD_LOCAL
        f.write(hex(self._local) + b'\n')
        for rtype, data in irecords:
            if rtype == RECORD_MERGED:
                f.write(b'%s\n' % _droponode(data))
        f.close()

    def _writerecordsv2(self, records):
        """Write current state on disk in a version 2 file

        See the docstring for _readrecordsv2 for why we use 't'."""
        # these are the records that all version 2 clients can read
        allowlist = (RECORD_LOCAL, RECORD_OTHER, RECORD_MERGED)
        f = self._repo.vfs(self.statepathv2, b'wb')
        for key, data in records:
            assert len(key) == 1
            if key not in allowlist:
                key, data = RECORD_OVERRIDE, b'%s%s' % (key, data)
            format = b'>sI%is' % len(data)
            f.write(_pack(format, key, len(data), data))
        f.close()

    @staticmethod
    def getlocalkey(path):
        """hash the path of a local file context for storage in the .hg/merge
        directory."""

        return hex(hashutil.sha1(path).digest())

    def add(self, fcl, fco, fca, fd):
        """add a new (potentially?) conflicting file the merge state
        fcl: file context for local,
        fco: file context for remote,
        fca: file context for ancestors,
        fd:  file path of the resulting merge.

        note: also write the local version to the `.hg/merge` directory.
        """
        if fcl.isabsent():
            localkey = nullhex
        else:
            localkey = mergestate.getlocalkey(fcl.path())
            self._repo.vfs.write(b'merge/' + localkey, fcl.data())
        self._state[fd] = [
            MERGE_RECORD_UNRESOLVED,
            localkey,
            fcl.path(),
            fca.path(),
            hex(fca.filenode()),
            fco.path(),
            hex(fco.filenode()),
            fcl.flags(),
        ]
        self._stateextras[fd] = {b'ancestorlinknode': hex(fca.node())}
        self._dirty = True

    def addpath(self, path, frename, forigin):
        """add a new conflicting path to the merge state
        path:    the path that conflicts
        frename: the filename the conflicting file was renamed to
        forigin: origin of the file ('l' or 'r' for local/remote)
        """
        self._state[path] = [MERGE_RECORD_UNRESOLVED_PATH, frename, forigin]
        self._dirty = True

    def addmergedother(self, path):
        self._state[path] = [MERGE_RECORD_MERGED_OTHER, nullhex, nullhex]
        self._dirty = True

    def __contains__(self, dfile):
        return dfile in self._state

    def __getitem__(self, dfile):
        return self._state[dfile][0]

    def __iter__(self):
        return iter(sorted(self._state))

    def files(self):
        return self._state.keys()

    def mark(self, dfile, state):
        self._state[dfile][0] = state
        self._dirty = True

    def mdstate(self):
        return self._mdstate

    def unresolved(self):
        """Obtain the paths of unresolved files."""

        for f, entry in pycompat.iteritems(self._state):
            if entry[0] in (
                MERGE_RECORD_UNRESOLVED,
                MERGE_RECORD_UNRESOLVED_PATH,
            ):
                yield f

    def driverresolved(self):
        """Obtain the paths of driver-resolved files."""

        for f, entry in self._state.items():
            if entry[0] == MERGE_RECORD_DRIVER_RESOLVED:
                yield f

    def extras(self, filename):
        return self._stateextras.setdefault(filename, {})

    def _resolve(self, preresolve, dfile, wctx):
        """rerun merge process for file path `dfile`"""
        if self[dfile] in (MERGE_RECORD_RESOLVED, MERGE_RECORD_DRIVER_RESOLVED):
            return True, 0
        if self._state[dfile][0] == MERGE_RECORD_MERGED_OTHER:
            return True, 0
        stateentry = self._state[dfile]
        state, localkey, lfile, afile, anode, ofile, onode, flags = stateentry
        octx = self._repo[self._other]
        extras = self.extras(dfile)
        anccommitnode = extras.get(b'ancestorlinknode')
        if anccommitnode:
            actx = self._repo[anccommitnode]
        else:
            actx = None
        fcd = self._filectxorabsent(localkey, wctx, dfile)
        fco = self._filectxorabsent(onode, octx, ofile)
        # TODO: move this to filectxorabsent
        fca = self._repo.filectx(afile, fileid=anode, changectx=actx)
        # "premerge" x flags
        flo = fco.flags()
        fla = fca.flags()
        if b'x' in flags + flo + fla and b'l' not in flags + flo + fla:
            if fca.node() == nullid and flags != flo:
                if preresolve:
                    self._repo.ui.warn(
                        _(
                            b'warning: cannot merge flags for %s '
                            b'without common ancestor - keeping local flags\n'
                        )
                        % afile
                    )
            elif flags == fla:
                flags = flo
        if preresolve:
            # restore local
            if localkey != nullhex:
                f = self._repo.vfs(b'merge/' + localkey)
                wctx[dfile].write(f.read(), flags)
                f.close()
            else:
                wctx[dfile].remove(ignoremissing=True)
            complete, r, deleted = filemerge.premerge(
                self._repo,
                wctx,
                self._local,
                lfile,
                fcd,
                fco,
                fca,
                labels=self._labels,
            )
        else:
            complete, r, deleted = filemerge.filemerge(
                self._repo,
                wctx,
                self._local,
                lfile,
                fcd,
                fco,
                fca,
                labels=self._labels,
            )
        if r is None:
            # no real conflict
            del self._state[dfile]
            self._stateextras.pop(dfile, None)
            self._dirty = True
        elif not r:
            self.mark(dfile, MERGE_RECORD_RESOLVED)

        if complete:
            action = None
            if deleted:
                if fcd.isabsent():
                    # dc: local picked. Need to drop if present, which may
                    # happen on re-resolves.
                    action = ACTION_FORGET
                else:
                    # cd: remote picked (or otherwise deleted)
                    action = ACTION_REMOVE
            else:
                if fcd.isabsent():  # dc: remote picked
                    action = ACTION_GET
                elif fco.isabsent():  # cd: local picked
                    if dfile in self.localctx:
                        action = ACTION_ADD_MODIFIED
                    else:
                        action = ACTION_ADD
                # else: regular merges (no action necessary)
            self._results[dfile] = r, action

        return complete, r

    def _filectxorabsent(self, hexnode, ctx, f):
        if hexnode == nullhex:
            return filemerge.absentfilectx(ctx, f)
        else:
            return ctx[f]

    def preresolve(self, dfile, wctx):
        """run premerge process for dfile

        Returns whether the merge is complete, and the exit code."""
        return self._resolve(True, dfile, wctx)

    def resolve(self, dfile, wctx):
        """run merge process (assuming premerge was run) for dfile

        Returns the exit code of the merge."""
        return self._resolve(False, dfile, wctx)[1]

    def counts(self):
        """return counts for updated, merged and removed files in this
        session"""
        updated, merged, removed = 0, 0, 0
        for r, action in pycompat.itervalues(self._results):
            if r is None:
                updated += 1
            elif r == 0:
                if action == ACTION_REMOVE:
                    removed += 1
                else:
                    merged += 1
        return updated, merged, removed

    def unresolvedcount(self):
        """get unresolved count for this merge (persistent)"""
        return len(list(self.unresolved()))

    def actions(self):
        """return lists of actions to perform on the dirstate"""
        actions = {
            ACTION_REMOVE: [],
            ACTION_FORGET: [],
            ACTION_ADD: [],
            ACTION_ADD_MODIFIED: [],
            ACTION_GET: [],
        }
        for f, (r, action) in pycompat.iteritems(self._results):
            if action is not None:
                actions[action].append((f, None, b"merge result"))
        return actions

    def recordactions(self):
        """record remove/add/get actions in the dirstate"""
        branchmerge = self._repo.dirstate.p2() != nullid
        recordupdates(self._repo, self.actions(), branchmerge, None)

    def queueremove(self, f):
        """queues a file to be removed from the dirstate

        Meant for use by custom merge drivers."""
        self._results[f] = 0, ACTION_REMOVE

    def queueadd(self, f):
        """queues a file to be added to the dirstate

        Meant for use by custom merge drivers."""
        self._results[f] = 0, ACTION_ADD

    def queueget(self, f):
        """queues a file to be marked modified in the dirstate

        Meant for use by custom merge drivers."""
        self._results[f] = 0, ACTION_GET


def recordupdates(repo, actions, branchmerge, getfiledata):
    """record merge actions to the dirstate"""
    # remove (must come first)
    for f, args, msg in actions.get(ACTION_REMOVE, []):
        if branchmerge:
            repo.dirstate.remove(f)
        else:
            repo.dirstate.drop(f)

    # forget (must come first)
    for f, args, msg in actions.get(ACTION_FORGET, []):
        repo.dirstate.drop(f)

    # resolve path conflicts
    for f, args, msg in actions.get(ACTION_PATH_CONFLICT_RESOLVE, []):
        (f0,) = args
        origf0 = repo.dirstate.copied(f0) or f0
        repo.dirstate.add(f)
        repo.dirstate.copy(origf0, f)
        if f0 == origf0:
            repo.dirstate.remove(f0)
        else:
            repo.dirstate.drop(f0)

    # re-add
    for f, args, msg in actions.get(ACTION_ADD, []):
        repo.dirstate.add(f)

    # re-add/mark as modified
    for f, args, msg in actions.get(ACTION_ADD_MODIFIED, []):
        if branchmerge:
            repo.dirstate.normallookup(f)
        else:
            repo.dirstate.add(f)

    # exec change
    for f, args, msg in actions.get(ACTION_EXEC, []):
        repo.dirstate.normallookup(f)

    # keep
    for f, args, msg in actions.get(ACTION_KEEP, []):
        pass

    # get
    for f, args, msg in actions.get(ACTION_GET, []):
        if branchmerge:
            repo.dirstate.otherparent(f)
        else:
            parentfiledata = getfiledata[f] if getfiledata else None
            repo.dirstate.normal(f, parentfiledata=parentfiledata)

    # merge
    for f, args, msg in actions.get(ACTION_MERGE, []):
        f1, f2, fa, move, anc = args
        if branchmerge:
            # We've done a branch merge, mark this file as merged
            # so that we properly record the merger later
            repo.dirstate.merge(f)
            if f1 != f2:  # copy/rename
                if move:
                    repo.dirstate.remove(f1)
                if f1 != f:
                    repo.dirstate.copy(f1, f)
                else:
                    repo.dirstate.copy(f2, f)
        else:
            # We've update-merged a locally modified file, so
            # we set the dirstate to emulate a normal checkout
            # of that file some time in the past. Thus our
            # merge will appear as a normal local file
            # modification.
            if f2 == f:  # file not locally copied/moved
                repo.dirstate.normallookup(f)
            if move:
                repo.dirstate.drop(f1)

    # directory rename, move local
    for f, args, msg in actions.get(ACTION_DIR_RENAME_MOVE_LOCAL, []):
        f0, flag = args
        if branchmerge:
            repo.dirstate.add(f)
            repo.dirstate.remove(f0)
            repo.dirstate.copy(f0, f)
        else:
            repo.dirstate.normal(f)
            repo.dirstate.drop(f0)

    # directory rename, get
    for f, args, msg in actions.get(ACTION_LOCAL_DIR_RENAME_GET, []):
        f0, flag = args
        if branchmerge:
            repo.dirstate.add(f)
            repo.dirstate.copy(f0, f)
        else:
            repo.dirstate.normal(f)
