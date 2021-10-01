# dirstatemap.py
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import errno

from .i18n import _

from . import (
    error,
    pathutil,
    policy,
    pycompat,
    txnutil,
    util,
)

from .dirstateutils import (
    docket as docketmod,
)

parsers = policy.importmod('parsers')
rustmod = policy.importrust('dirstate')

propertycache = util.propertycache

if rustmod is None:
    DirstateItem = parsers.DirstateItem
else:
    DirstateItem = rustmod.DirstateItem

rangemask = 0x7FFFFFFF


class _dirstatemapcommon(object):
    """
    Methods that are identical for both implementations of the dirstatemap
    class, with and without Rust extensions enabled.
    """

    # please pytype

    _map = None
    copymap = None

    def __init__(self, ui, opener, root, nodeconstants, use_dirstate_v2):
        self._use_dirstate_v2 = use_dirstate_v2
        self._nodeconstants = nodeconstants
        self._ui = ui
        self._opener = opener
        self._root = root
        self._filename = b'dirstate'
        self._nodelen = 20  # Also update Rust code when changing this!
        self._parents = None
        self._dirtyparents = False

        # for consistent view between _pl() and _read() invocations
        self._pendingmode = None

    def preload(self):
        """Loads the underlying data, if it's not already loaded"""
        self._map

    def get(self, key, default=None):
        return self._map.get(key, default)

    def __len__(self):
        return len(self._map)

    def __iter__(self):
        return iter(self._map)

    def __contains__(self, key):
        return key in self._map

    def __getitem__(self, item):
        return self._map[item]

    ### sub-class utility method
    #
    # Use to allow for generic implementation of some method while still coping
    # with minor difference between implementation.

    def _dirs_incr(self, filename, old_entry=None):
        """incremente the dirstate counter if applicable

        This might be a no-op for some subclass who deal with directory
        tracking in a different way.
        """

    def _dirs_decr(self, filename, old_entry=None, remove_variant=False):
        """decremente the dirstate counter if applicable

        This might be a no-op for some subclass who deal with directory
        tracking in a different way.
        """

    def _refresh_entry(self, f, entry):
        """record updated state of an entry"""

    ### method to manipulate the entries

    def set_untracked(self, f):
        """Mark a file as no longer tracked in the dirstate map"""
        entry = self.get(f)
        if entry is None:
            return False
        else:
            self._dirs_decr(f, old_entry=entry, remove_variant=not entry.added)
            if not entry.merged:
                self.copymap.pop(f, None)
            entry.set_untracked()
            self._refresh_entry(f, entry)
            return True


class dirstatemap(_dirstatemapcommon):
    """Map encapsulating the dirstate's contents.

    The dirstate contains the following state:

    - `identity` is the identity of the dirstate file, which can be used to
      detect when changes have occurred to the dirstate file.

    - `parents` is a pair containing the parents of the working copy. The
      parents are updated by calling `setparents`.

    - the state map maps filenames to tuples of (state, mode, size, mtime),
      where state is a single character representing 'normal', 'added',
      'removed', or 'merged'. It is read by treating the dirstate as a
      dict.  File state is updated by calling various methods (see each
      documentation for details):

      - `reset_state`,
      - `set_tracked`
      - `set_untracked`
      - `set_clean`
      - `set_possibly_dirty`

    - `copymap` maps destination filenames to their source filename.

    The dirstate also provides the following views onto the state:

    - `filefoldmap` is a dict mapping normalized filenames to the denormalized
      form that they appear as in the dirstate.

    - `dirfoldmap` is a dict mapping normalized directory names to the
      denormalized form that they appear as in the dirstate.
    """

    def __init__(self, ui, opener, root, nodeconstants, use_dirstate_v2):
        super(dirstatemap, self).__init__(
            ui, opener, root, nodeconstants, use_dirstate_v2
        )
        if self._use_dirstate_v2:
            msg = "Dirstate V2 not supportedi"
            msg += "(should have detected unsupported requirement)"
            raise error.ProgrammingError(msg)

    ### Core data storage and access

    @propertycache
    def _map(self):
        self._map = {}
        self.read()
        return self._map

    @propertycache
    def copymap(self):
        self.copymap = {}
        self._map
        return self.copymap

    def clear(self):
        self._map.clear()
        self.copymap.clear()
        self.setparents(self._nodeconstants.nullid, self._nodeconstants.nullid)
        util.clearcachedproperty(self, b"_dirs")
        util.clearcachedproperty(self, b"_alldirs")
        util.clearcachedproperty(self, b"filefoldmap")
        util.clearcachedproperty(self, b"dirfoldmap")

    def items(self):
        return pycompat.iteritems(self._map)

    # forward for python2,3 compat
    iteritems = items

    def debug_iter(self, all):
        """
        Return an iterator of (filename, state, mode, size, mtime) tuples

        `all` is unused when Rust is not enabled
        """
        for (filename, item) in self.items():
            yield (filename, item.state, item.mode, item.size, item.mtime)

    def keys(self):
        return self._map.keys()

    ### reading/setting parents

    def parents(self):
        if not self._parents:
            try:
                fp = self._opendirstatefile()
                st = fp.read(2 * self._nodelen)
                fp.close()
            except IOError as err:
                if err.errno != errno.ENOENT:
                    raise
                # File doesn't exist, so the current state is empty
                st = b''

            l = len(st)
            if l == self._nodelen * 2:
                self._parents = (
                    st[: self._nodelen],
                    st[self._nodelen : 2 * self._nodelen],
                )
            elif l == 0:
                self._parents = (
                    self._nodeconstants.nullid,
                    self._nodeconstants.nullid,
                )
            else:
                raise error.Abort(
                    _(b'working directory state appears damaged!')
                )

        return self._parents

    def setparents(self, p1, p2, fold_p2=False):
        self._parents = (p1, p2)
        self._dirtyparents = True
        copies = {}
        if fold_p2:
            for f, s in pycompat.iteritems(self._map):
                # Discard "merged" markers when moving away from a merge state
                if s.merged or s.from_p2:
                    source = self.copymap.pop(f, None)
                    if source:
                        copies[f] = source
                    s.drop_merge_data()
        return copies

    ### disk interaction

    def read(self):
        # ignore HG_PENDING because identity is used only for writing
        self.identity = util.filestat.frompath(
            self._opener.join(self._filename)
        )

        try:
            fp = self._opendirstatefile()
            try:
                st = fp.read()
            finally:
                fp.close()
        except IOError as err:
            if err.errno != errno.ENOENT:
                raise
            return
        if not st:
            return

        if util.safehasattr(parsers, b'dict_new_presized'):
            # Make an estimate of the number of files in the dirstate based on
            # its size. This trades wasting some memory for avoiding costly
            # resizes. Each entry have a prefix of 17 bytes followed by one or
            # two path names. Studies on various large-scale real-world repositories
            # found 54 bytes a reasonable upper limit for the average path names.
            # Copy entries are ignored for the sake of this estimate.
            self._map = parsers.dict_new_presized(len(st) // 71)

        # Python's garbage collector triggers a GC each time a certain number
        # of container objects (the number being defined by
        # gc.get_threshold()) are allocated. parse_dirstate creates a tuple
        # for each file in the dirstate. The C version then immediately marks
        # them as not to be tracked by the collector. However, this has no
        # effect on when GCs are triggered, only on what objects the GC looks
        # into. This means that O(number of files) GCs are unavoidable.
        # Depending on when in the process's lifetime the dirstate is parsed,
        # this can get very expensive. As a workaround, disable GC while
        # parsing the dirstate.
        #
        # (we cannot decorate the function directly since it is in a C module)
        parse_dirstate = util.nogc(parsers.parse_dirstate)
        p = parse_dirstate(self._map, self.copymap, st)
        if not self._dirtyparents:
            self.setparents(*p)

        # Avoid excess attribute lookups by fast pathing certain checks
        self.__contains__ = self._map.__contains__
        self.__getitem__ = self._map.__getitem__
        self.get = self._map.get

    def write(self, _tr, st, now):
        d = parsers.pack_dirstate(self._map, self.copymap, self.parents(), now)
        st.write(d)
        st.close()
        self._dirtyparents = False

    def _opendirstatefile(self):
        fp, mode = txnutil.trypending(self._root, self._opener, self._filename)
        if self._pendingmode is not None and self._pendingmode != mode:
            fp.close()
            raise error.Abort(
                _(b'working directory state may be changed parallelly')
            )
        self._pendingmode = mode
        return fp

    @propertycache
    def identity(self):
        self._map
        return self.identity

    ### code related to maintaining and accessing "extra" property
    # (e.g. "has_dir")

    def _dirs_incr(self, filename, old_entry=None):
        """incremente the dirstate counter if applicable"""
        if (
            old_entry is None or old_entry.removed
        ) and "_dirs" in self.__dict__:
            self._dirs.addpath(filename)
        if old_entry is None and "_alldirs" in self.__dict__:
            self._alldirs.addpath(filename)

    def _dirs_decr(self, filename, old_entry=None, remove_variant=False):
        """decremente the dirstate counter if applicable"""
        if old_entry is not None:
            if "_dirs" in self.__dict__ and not old_entry.removed:
                self._dirs.delpath(filename)
            if "_alldirs" in self.__dict__ and not remove_variant:
                self._alldirs.delpath(filename)
        elif remove_variant and "_alldirs" in self.__dict__:
            self._alldirs.addpath(filename)
        if "filefoldmap" in self.__dict__:
            normed = util.normcase(filename)
            self.filefoldmap.pop(normed, None)

    @propertycache
    def filefoldmap(self):
        """Returns a dictionary mapping normalized case paths to their
        non-normalized versions.
        """
        try:
            makefilefoldmap = parsers.make_file_foldmap
        except AttributeError:
            pass
        else:
            return makefilefoldmap(
                self._map, util.normcasespec, util.normcasefallback
            )

        f = {}
        normcase = util.normcase
        for name, s in pycompat.iteritems(self._map):
            if not s.removed:
                f[normcase(name)] = name
        f[b'.'] = b'.'  # prevents useless util.fspath() invocation
        return f

    @propertycache
    def dirfoldmap(self):
        f = {}
        normcase = util.normcase
        for name in self._dirs:
            f[normcase(name)] = name
        return f

    def hastrackeddir(self, d):
        """
        Returns True if the dirstate contains a tracked (not removed) file
        in this directory.
        """
        return d in self._dirs

    def hasdir(self, d):
        """
        Returns True if the dirstate contains a file (tracked or removed)
        in this directory.
        """
        return d in self._alldirs

    @propertycache
    def _dirs(self):
        return pathutil.dirs(self._map, only_tracked=True)

    @propertycache
    def _alldirs(self):
        return pathutil.dirs(self._map)

    ### code related to manipulation of entries and copy-sources

    def _refresh_entry(self, f, entry):
        if not entry.any_tracked:
            self._map.pop(f, None)

    def set_possibly_dirty(self, filename):
        """record that the current state of the file on disk is unknown"""
        self[filename].set_possibly_dirty()

    def set_clean(self, filename, mode, size, mtime):
        """mark a file as back to a clean state"""
        entry = self[filename]
        mtime = mtime & rangemask
        size = size & rangemask
        entry.set_clean(mode, size, mtime)
        self.copymap.pop(filename, None)

    def reset_state(
        self,
        filename,
        wc_tracked=False,
        p1_tracked=False,
        p2_tracked=False,
        merged=False,
        clean_p1=False,
        clean_p2=False,
        possibly_dirty=False,
        parentfiledata=None,
    ):
        """Set a entry to a given state, diregarding all previous state

        This is to be used by the part of the dirstate API dedicated to
        adjusting the dirstate after a update/merge.

        note: calling this might result to no entry existing at all if the
        dirstate map does not see any point at having one for this file
        anymore.
        """
        if merged and (clean_p1 or clean_p2):
            msg = b'`merged` argument incompatible with `clean_p1`/`clean_p2`'
            raise error.ProgrammingError(msg)
        # copy information are now outdated
        # (maybe new information should be in directly passed to this function)
        self.copymap.pop(filename, None)

        if not (p1_tracked or p2_tracked or wc_tracked):
            old_entry = self._map.pop(filename, None)
            self._dirs_decr(filename, old_entry=old_entry)
            self.copymap.pop(filename, None)
            return
        elif merged:
            pass
        elif not (p1_tracked or p2_tracked) and wc_tracked:
            pass  # file is added, nothing special to adjust
        elif (p1_tracked or p2_tracked) and not wc_tracked:
            pass
        elif clean_p2 and wc_tracked:
            pass
        elif not p1_tracked and p2_tracked and wc_tracked:
            clean_p2 = True
        elif possibly_dirty:
            pass
        elif wc_tracked:
            # this is a "normal" file
            if parentfiledata is None:
                msg = b'failed to pass parentfiledata for a normal file: %s'
                msg %= filename
                raise error.ProgrammingError(msg)
        else:
            assert False, 'unreachable'

        old_entry = self._map.get(filename)
        self._dirs_incr(filename, old_entry)
        entry = DirstateItem(
            wc_tracked=wc_tracked,
            p1_tracked=p1_tracked,
            p2_tracked=p2_tracked,
            merged=merged,
            clean_p1=clean_p1,
            clean_p2=clean_p2,
            possibly_dirty=possibly_dirty,
            parentfiledata=parentfiledata,
        )
        self._map[filename] = entry

    def set_tracked(self, filename):
        new = False
        entry = self.get(filename)
        if entry is None:
            self._dirs_incr(filename)
            entry = DirstateItem(
                p1_tracked=False,
                p2_tracked=False,
                wc_tracked=True,
                merged=False,
                clean_p1=False,
                clean_p2=False,
                possibly_dirty=False,
                parentfiledata=None,
            )
            self._map[filename] = entry
            new = True
        elif not entry.tracked:
            self._dirs_incr(filename, entry)
            entry.set_tracked()
            new = True
        else:
            # XXX This is probably overkill for more case, but we need this to
            # fully replace the `normallookup` call with `set_tracked` one.
            # Consider smoothing this in the future.
            self.set_possibly_dirty(filename)
        return new


if rustmod is not None:

    class dirstatemap(_dirstatemapcommon):
        def __init__(self, ui, opener, root, nodeconstants, use_dirstate_v2):
            super(dirstatemap, self).__init__(
                ui, opener, root, nodeconstants, use_dirstate_v2
            )
            self._docket = None

        ### Core data storage and access

        @property
        def docket(self):
            if not self._docket:
                if not self._use_dirstate_v2:
                    raise error.ProgrammingError(
                        b'dirstate only has a docket in v2 format'
                    )
                self._docket = docketmod.DirstateDocket.parse(
                    self._readdirstatefile(), self._nodeconstants
                )
            return self._docket

        @propertycache
        def _map(self):
            """
            Fills the Dirstatemap when called.
            """
            # ignore HG_PENDING because identity is used only for writing
            self.identity = util.filestat.frompath(
                self._opener.join(self._filename)
            )

            if self._use_dirstate_v2:
                if self.docket.uuid:
                    # TODO: use mmap when possible
                    data = self._opener.read(self.docket.data_filename())
                else:
                    data = b''
                self._map = rustmod.DirstateMap.new_v2(
                    data, self.docket.data_size, self.docket.tree_metadata
                )
                parents = self.docket.parents
            else:
                self._map, parents = rustmod.DirstateMap.new_v1(
                    self._readdirstatefile()
                )

            if parents and not self._dirtyparents:
                self.setparents(*parents)

            self.__contains__ = self._map.__contains__
            self.__getitem__ = self._map.__getitem__
            self.get = self._map.get
            return self._map

        @property
        def copymap(self):
            return self._map.copymap()

        def debug_iter(self, all):
            """
            Return an iterator of (filename, state, mode, size, mtime) tuples

            `all`: also include with `state == b' '` dirstate tree nodes that
            don't have an associated `DirstateItem`.

            """
            return self._map.debug_iter(all)

        def clear(self):
            self._map.clear()
            self.setparents(
                self._nodeconstants.nullid, self._nodeconstants.nullid
            )
            util.clearcachedproperty(self, b"_dirs")
            util.clearcachedproperty(self, b"_alldirs")
            util.clearcachedproperty(self, b"dirfoldmap")

        def items(self):
            return self._map.items()

        # forward for python2,3 compat
        iteritems = items

        def keys(self):
            return iter(self._map)

        ### reading/setting parents

        def setparents(self, p1, p2, fold_p2=False):
            self._parents = (p1, p2)
            self._dirtyparents = True
            copies = {}
            if fold_p2:
                # Collect into an intermediate list to avoid a `RuntimeError`
                # exception due to mutation during iteration.
                # TODO: move this the whole loop to Rust where `iter_mut`
                # enables in-place mutation of elements of a collection while
                # iterating it, without mutating the collection itself.
                candidatefiles = [
                    (f, s)
                    for f, s in self._map.items()
                    if s.merged or s.from_p2
                ]
                for f, s in candidatefiles:
                    # Discard "merged" markers when moving away from a merge state
                    if s.merged:
                        source = self.copymap.get(f)
                        if source:
                            copies[f] = source
                        self.reset_state(
                            f,
                            wc_tracked=True,
                            p1_tracked=True,
                            possibly_dirty=True,
                        )
                    # Also fix up otherparent markers
                    elif s.from_p2:
                        source = self.copymap.get(f)
                        if source:
                            copies[f] = source
                        self.reset_state(
                            f,
                            p1_tracked=False,
                            wc_tracked=True,
                        )
            return copies

        def parents(self):
            if not self._parents:
                if self._use_dirstate_v2:
                    self._parents = self.docket.parents
                else:
                    read_len = self._nodelen * 2
                    st = self._readdirstatefile(read_len)
                    l = len(st)
                    if l == read_len:
                        self._parents = (
                            st[: self._nodelen],
                            st[self._nodelen : 2 * self._nodelen],
                        )
                    elif l == 0:
                        self._parents = (
                            self._nodeconstants.nullid,
                            self._nodeconstants.nullid,
                        )
                    else:
                        raise error.Abort(
                            _(b'working directory state appears damaged!')
                        )

            return self._parents

        ### disk interaction

        @propertycache
        def identity(self):
            self._map
            return self.identity

        def write(self, tr, st, now):
            if not self._use_dirstate_v2:
                p1, p2 = self.parents()
                packed = self._map.write_v1(p1, p2, now)
                st.write(packed)
                st.close()
                self._dirtyparents = False
                return

            # We can only append to an existing data file if there is one
            can_append = self.docket.uuid is not None
            packed, meta, append = self._map.write_v2(now, can_append)
            if append:
                docket = self.docket
                data_filename = docket.data_filename()
                if tr:
                    tr.add(data_filename, docket.data_size)
                with self._opener(data_filename, b'r+b') as fp:
                    fp.seek(docket.data_size)
                    assert fp.tell() == docket.data_size
                    written = fp.write(packed)
                    if written is not None:  # py2 may return None
                        assert written == len(packed), (written, len(packed))
                docket.data_size += len(packed)
                docket.parents = self.parents()
                docket.tree_metadata = meta
                st.write(docket.serialize())
                st.close()
            else:
                old_docket = self.docket
                new_docket = docketmod.DirstateDocket.with_new_uuid(
                    self.parents(), len(packed), meta
                )
                data_filename = new_docket.data_filename()
                if tr:
                    tr.add(data_filename, 0)
                self._opener.write(data_filename, packed)
                # Write the new docket after the new data file has been
                # written. Because `st` was opened with `atomictemp=True`,
                # the actual `.hg/dirstate` file is only affected on close.
                st.write(new_docket.serialize())
                st.close()
                # Remove the old data file after the new docket pointing to
                # the new data file was written.
                if old_docket.uuid:
                    data_filename = old_docket.data_filename()
                    unlink = lambda _tr=None: self._opener.unlink(data_filename)
                    if tr:
                        category = b"dirstate-v2-clean-" + old_docket.uuid
                        tr.addpostclose(category, unlink)
                    else:
                        unlink()
                self._docket = new_docket
            # Reload from the newly-written file
            util.clearcachedproperty(self, b"_map")
            self._dirtyparents = False

        def _opendirstatefile(self):
            fp, mode = txnutil.trypending(
                self._root, self._opener, self._filename
            )
            if self._pendingmode is not None and self._pendingmode != mode:
                fp.close()
                raise error.Abort(
                    _(b'working directory state may be changed parallelly')
                )
            self._pendingmode = mode
            return fp

        def _readdirstatefile(self, size=-1):
            try:
                with self._opendirstatefile() as fp:
                    return fp.read(size)
            except IOError as err:
                if err.errno != errno.ENOENT:
                    raise
                # File doesn't exist, so the current state is empty
                return b''

        ### code related to maintaining and accessing "extra" property
        # (e.g. "has_dir")

        @propertycache
        def filefoldmap(self):
            """Returns a dictionary mapping normalized case paths to their
            non-normalized versions.
            """
            return self._map.filefoldmapasdict()

        def hastrackeddir(self, d):
            return self._map.hastrackeddir(d)

        def hasdir(self, d):
            return self._map.hasdir(d)

        @propertycache
        def dirfoldmap(self):
            f = {}
            normcase = util.normcase
            for name in self._map.tracked_dirs():
                f[normcase(name)] = name
            return f

        ### code related to manipulation of entries and copy-sources

        def _refresh_entry(self, f, entry):
            if not entry.any_tracked:
                self._map.drop_item_and_copy_source(f)
            else:
                self._map.addfile(f, entry)

        def set_possibly_dirty(self, filename):
            """record that the current state of the file on disk is unknown"""
            entry = self[filename]
            entry.set_possibly_dirty()
            self._map.set_dirstate_item(filename, entry)

        def set_clean(self, filename, mode, size, mtime):
            """mark a file as back to a clean state"""
            entry = self[filename]
            mtime = mtime & rangemask
            size = size & rangemask
            entry.set_clean(mode, size, mtime)
            self._map.set_dirstate_item(filename, entry)
            self._map.copymap().pop(filename, None)

        def __setitem__(self, key, value):
            assert isinstance(value, DirstateItem)
            self._map.set_dirstate_item(key, value)

        def reset_state(
            self,
            filename,
            wc_tracked=False,
            p1_tracked=False,
            p2_tracked=False,
            merged=False,
            clean_p1=False,
            clean_p2=False,
            possibly_dirty=False,
            parentfiledata=None,
        ):
            """Set a entry to a given state, disregarding all previous state

            This is to be used by the part of the dirstate API dedicated to
            adjusting the dirstate after a update/merge.

            note: calling this might result to no entry existing at all if the
            dirstate map does not see any point at having one for this file
            anymore.
            """
            if merged and (clean_p1 or clean_p2):
                msg = (
                    b'`merged` argument incompatible with `clean_p1`/`clean_p2`'
                )
                raise error.ProgrammingError(msg)
            # copy information are now outdated
            # (maybe new information should be in directly passed to this function)
            self.copymap.pop(filename, None)

            if not (p1_tracked or p2_tracked or wc_tracked):
                self._map.drop_item_and_copy_source(filename)
            elif merged:
                # XXX might be merged and removed ?
                entry = self.get(filename)
                if entry is not None and entry.tracked:
                    # XXX mostly replicate dirstate.other parent.  We should get
                    # the higher layer to pass us more reliable data where `merged`
                    # actually mean merged. Dropping the else clause will show
                    # failure in `test-graft.t`
                    self.addfile(filename, merged=True)
                else:
                    self.addfile(filename, from_p2=True)
            elif not (p1_tracked or p2_tracked) and wc_tracked:
                self.addfile(
                    filename, added=True, possibly_dirty=possibly_dirty
                )
            elif (p1_tracked or p2_tracked) and not wc_tracked:
                # XXX might be merged and removed ?
                self[filename] = DirstateItem.from_v1_data(b'r', 0, 0, 0)
            elif clean_p2 and wc_tracked:
                if p1_tracked or self.get(filename) is not None:
                    # XXX the `self.get` call is catching some case in
                    # `test-merge-remove.t` where the file is tracked in p1, the
                    # p1_tracked argument is False.
                    #
                    # In addition, this seems to be a case where the file is marked
                    # as merged without actually being the result of a merge
                    # action. So thing are not ideal here.
                    self.addfile(filename, merged=True)
                else:
                    self.addfile(filename, from_p2=True)
            elif not p1_tracked and p2_tracked and wc_tracked:
                self.addfile(
                    filename, from_p2=True, possibly_dirty=possibly_dirty
                )
            elif possibly_dirty:
                self.addfile(filename, possibly_dirty=possibly_dirty)
            elif wc_tracked:
                # this is a "normal" file
                if parentfiledata is None:
                    msg = b'failed to pass parentfiledata for a normal file: %s'
                    msg %= filename
                    raise error.ProgrammingError(msg)
                mode, size, mtime = parentfiledata
                self.addfile(filename, mode=mode, size=size, mtime=mtime)
            else:
                assert False, 'unreachable'

        def set_tracked(self, filename):
            new = False
            entry = self.get(filename)
            if entry is None:
                self.addfile(filename, added=True)
                new = True
            elif not entry.tracked:
                entry.set_tracked()
                self._map.set_dirstate_item(filename, entry)
                new = True
            else:
                # XXX This is probably overkill for more case, but we need this to
                # fully replace the `normallookup` call with `set_tracked` one.
                # Consider smoothing this in the future.
                self.set_possibly_dirty(filename)
            return new

        ### Legacy method we need to get rid of

        def addfile(
            self,
            f,
            mode=0,
            size=None,
            mtime=None,
            added=False,
            merged=False,
            from_p2=False,
            possibly_dirty=False,
        ):
            if added:
                assert not possibly_dirty
                assert not from_p2
                item = DirstateItem.new_added()
            elif merged:
                assert not possibly_dirty
                assert not from_p2
                item = DirstateItem.new_merged()
            elif from_p2:
                assert not possibly_dirty
                item = DirstateItem.new_from_p2()
            elif possibly_dirty:
                item = DirstateItem.new_possibly_dirty()
            else:
                assert size is not None
                assert mtime is not None
                size = size & rangemask
                mtime = mtime & rangemask
                item = DirstateItem.new_normal(mode, size, mtime)
            self._map.addfile(f, item)
            if added:
                self.copymap.pop(f, None)

        def removefile(self, *args, **kwargs):
            return self._map.removefile(*args, **kwargs)
