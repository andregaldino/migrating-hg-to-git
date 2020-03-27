from __future__ import absolute_import

from mercurial import (
    match as matchmod,
    pathutil,
    pycompat,
    util,
)
from mercurial.interfaces import (
    repository,
    util as interfaceutil,
)
from . import gitutil


pygit2 = gitutil.get_pygit2()


@interfaceutil.implementer(repository.imanifestdict)
class gittreemanifest(object):
    """Expose git trees (and optionally a builder's overlay) as a manifestdict.

    Very similar to mercurial.manifest.treemanifest.
    """

    def __init__(self, git_repo, root_tree, pending_changes):
        """Initializer.

        Args:
          git_repo: The git_repo we're walking (required to look up child
              trees).
          root_tree: The root Git tree object for this manifest.
          pending_changes: A dict in which pending changes will be
              tracked. The enclosing memgittreemanifestctx will use this to
              construct any required Tree objects in Git during it's
              `write()` method.
        """
        self._git_repo = git_repo
        self._tree = root_tree
        if pending_changes is None:
            pending_changes = {}
        # dict of path: Optional[Tuple(node, flags)]
        self._pending_changes = pending_changes

    def _resolve_entry(self, path):
        """Given a path, load its node and flags, or raise KeyError if missing.

        This takes into account any pending writes in the builder.
        """
        upath = pycompat.fsdecode(path)
        ent = None
        if path in self._pending_changes:
            val = self._pending_changes[path]
            if val is None:
                raise KeyError
            return val
        t = self._tree
        comps = upath.split('/')
        for comp in comps[:-1]:
            te = self._tree[comp]
            t = self._git_repo[te.id]
        ent = t[comps[-1]]
        if ent.filemode == pygit2.GIT_FILEMODE_BLOB:
            flags = b''
        elif ent.filemode == pygit2.GIT_FILEMODE_BLOB_EXECUTABLE:
            flags = b'x'
        elif ent.filemode == pygit2.GIT_FILEMODE_LINK:
            flags = b'l'
        else:
            raise ValueError('unsupported mode %s' % oct(ent.filemode))
        return ent.id.raw, flags

    def __getitem__(self, path):
        return self._resolve_entry(path)[0]

    def find(self, path):
        return self._resolve_entry(path)

    def __len__(self):
        return len(list(self.walk(matchmod.always())))

    def __nonzero__(self):
        try:
            next(iter(self))
            return True
        except StopIteration:
            return False

    __bool__ = __nonzero__

    def __contains__(self, path):
        try:
            self._resolve_entry(path)
            return True
        except KeyError:
            return False

    def iterkeys(self):
        return self.walk(matchmod.always())

    def keys(self):
        return list(self.iterkeys())

    def __iter__(self):
        return self.iterkeys()

    def __setitem__(self, path, node):
        self._pending_changes[path] = node, self.flags(path)

    def __delitem__(self, path):
        # TODO: should probably KeyError for already-deleted  files?
        self._pending_changes[path] = None

    def filesnotin(self, other, match=None):
        if match is not None:
            match = matchmod.badmatch(match, lambda path, msg: None)
            sm2 = set(other.walk(match))
            return {f for f in self.walk(match) if f not in sm2}
        return {f for f in self if f not in other}

    @util.propertycache
    def _dirs(self):
        return pathutil.dirs(self)

    def hasdir(self, dir):
        return dir in self._dirs

    def diff(self, other, match=None, clean=False):
        # TODO
        assert False

    def setflag(self, path, flag):
        node, unused_flag = self._resolve_entry(path)
        self._pending_changes[path] = node, flag

    def get(self, path, default=None):
        try:
            return self._resolve_entry(path)[0]
        except KeyError:
            return default

    def flags(self, path):
        try:
            return self._resolve_entry(path)[1]
        except KeyError:
            return b''

    def copy(self):
        pass

    def items(self):
        for f in self:
            # TODO: build a proper iterator version of this
            yield self[f]

    def iteritems(self):
        return self.items()

    def iterentries(self):
        for f in self:
            # TODO: build a proper iterator version of this
            yield self._resolve_entry(f)

    def text(self):
        assert False  # TODO can this method move out of the manifest iface?

    def _walkonetree(self, tree, match, subdir):
        for te in tree:
            # TODO: can we prune dir walks with the matcher?
            realname = subdir + pycompat.fsencode(te.name)
            if te.type == r'tree':
                for inner in self._walkonetree(
                    self._git_repo[te.id], match, realname + b'/'
                ):
                    yield inner
            if not match(realname):
                continue
            yield pycompat.fsencode(realname)

    def walk(self, match):
        # TODO: this is a very lazy way to merge in the pending
        # changes. There is absolutely room for optimization here by
        # being clever about walking over the sets...
        baseline = set(self._walkonetree(self._tree, match, b''))
        deleted = {p for p, v in self._pending_changes.items() if v is None}
        pend = {p for p in self._pending_changes if match(p)}
        return iter(sorted((baseline | pend) - deleted))


@interfaceutil.implementer(repository.imanifestrevisionstored)
class gittreemanifestctx(object):
    def __init__(self, repo, gittree):
        self._repo = repo
        self._tree = gittree

    def read(self):
        return gittreemanifest(self._repo, self._tree, None)

    def readfast(self, shallow=False):
        return self.read()

    def copy(self):
        # NB: it's important that we return a memgittreemanifestctx
        # because the caller expects a mutable manifest.
        return memgittreemanifestctx(self._repo, self._tree)

    def find(self, path):
        self.read()[path]


@interfaceutil.implementer(repository.imanifestrevisionwritable)
class memgittreemanifestctx(object):
    def __init__(self, repo, tree):
        self._repo = repo
        self._tree = tree
        # dict of path: Optional[Tuple(node, flags)]
        self._pending_changes = {}

    def read(self):
        return gittreemanifest(self._repo, self._tree, self._pending_changes)

    def copy(self):
        # TODO: if we have a builder in play, what should happen here?
        # Maybe we can shuffle copy() into the immutable interface.
        return memgittreemanifestctx(self._repo, self._tree)

    def write(self, transaction, link, p1, p2, added, removed, match=None):
        # We're not (for now, anyway) going to audit filenames, so we
        # can ignore added and removed.

        # TODO what does this match argument get used for? hopefully
        # just narrow?
        assert not match or isinstance(match, matchmod.alwaysmatcher)

        touched_dirs = pathutil.dirs(list(self._pending_changes))
        trees = {
            b'': self._tree,
        }
        # path: treebuilder
        builders = {
            b'': self._repo.TreeBuilder(self._tree),
        }
        # get a TreeBuilder for every tree in the touched_dirs set
        for d in sorted(touched_dirs, key=lambda x: (len(x), x)):
            if d == b'':
                # loaded root tree above
                continue
            comps = d.split(b'/')
            full = b''
            for part in comps:
                parent = trees[full]
                try:
                    new = self._repo[parent[pycompat.fsdecode(part)]]
                except KeyError:
                    # new directory
                    new = None
                full += b'/' + part
                if new is not None:
                    # existing directory
                    trees[full] = new
                    builders[full] = self._repo.TreeBuilder(new)
                else:
                    # new directory, use an empty dict to easily
                    # generate KeyError as any nested new dirs get
                    # created.
                    trees[full] = {}
                    builders[full] = self._repo.TreeBuilder()
        for f, info in self._pending_changes.items():
            if b'/' not in f:
                dirname = b''
                basename = f
            else:
                dirname, basename = f.rsplit(b'/', 1)
                dirname = b'/' + dirname
            if info is None:
                builders[dirname].remove(pycompat.fsdecode(basename))
            else:
                n, fl = info
                mode = {
                    b'': pygit2.GIT_FILEMODE_BLOB,
                    b'x': pygit2.GIT_FILEMODE_BLOB_EXECUTABLE,
                    b'l': pygit2.GIT_FILEMODE_LINK,
                }[fl]
                builders[dirname].insert(
                    pycompat.fsdecode(basename), gitutil.togitnode(n), mode
                )
        # This visits the buffered TreeBuilders in deepest-first
        # order, bubbling up the edits.
        for b in sorted(builders, key=len, reverse=True):
            if b == b'':
                break
            cb = builders[b]
            dn, bn = b.rsplit(b'/', 1)
            builders[dn].insert(
                pycompat.fsdecode(bn), cb.write(), pygit2.GIT_FILEMODE_TREE
            )
        return builders[b''].write().raw
