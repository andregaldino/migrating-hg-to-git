"""Create the race condition for issue6554

The persistent nodemap issues had an issue where a second writer could
overwrite the data that a previous write just wrote. The would break the append
only garantee of the persistent nodemap and could confuse reader. This
extensions create all the necessary synchronisation point to the race condition
to happen.

It involves 3 process <LEFT> (a writer) <RIGHT> (a writer) and <READER>

[1] <LEFT> take the lock and start a transaction
[2] <LEFT> updated `00changelog.i` with the new data
[3] <RIGHT> reads:
    - the new changelog index `00changelog.i`
    - the old `00changelog.n`
[4] <LEFT> update the persistent nodemap:
    - writing new data from the last valid offset
    - updating the docket (00changelog.n)
[5] <LEFT> release the lock
[6] <RIGHT> grab the lock and run `repo.invalidate`
[7] <READER> reads:
    - the changelog index after <LEFT> write
    - the nodemap docket after <LEFT> write
[8] <RIGHT> reload the changelog since `00changelog.n` changed
    /!\ This is the faulty part in issue 6554, the outdated docket is kept
[9] <RIGHT> write:
    - the changelog index (00changelog.i)
    - the nodemap data (00changelog*.nd)
      /!\ if the outdated docket is used, the write starts from the same ofset
      /!\ as in [4], overwriting data that <LEFT> wrote in step [4].
    - the nodemap docket (00changelog.n)
[10] <READER> reads the nodemap data from `00changelog*.nd`
     /!\ if step [9] was wrong, the data matching the docket that <READER>
     /!\ loaded have been overwritten and the expected root-nodes is no longer
     /!\ valid.
"""


import os

from mercurial.revlogutils.constants import KIND_CHANGELOG

from mercurial import (
    changelog,
    encoding,
    extensions,
    localrepo,
    node,
    pycompat,
    registrar,
    testing,
    util,
)

from mercurial.revlogutils import (
    nodemap as nodemaputil,
)

configtable = {}
configitem = registrar.configitem(configtable)

configitem(b'devel', b'nodemap-race.role', default=None)

cmdtable = {}
command = registrar.command(cmdtable)

LEFT = b'left'
RIGHT = b'right'
READER = b'reader'

SYNC_DIR = os.path.join(encoding.environ[b'TESTTMP'], b'sync-files')

# mark the end of step [1]
FILE_LEFT_LOCKED = os.path.join(SYNC_DIR, b'left-locked')
# mark that step [3] is ready to run.
FILE_RIGHT_READY_TO_LOCK = os.path.join(SYNC_DIR, b'right-ready-to-lock')

# mark the end of step [2]
FILE_LEFT_CL_DATA_WRITE = os.path.join(SYNC_DIR, b'left-data')
# mark the end of step [4]
FILE_LEFT_CL_NODEMAP_WRITE = os.path.join(SYNC_DIR, b'left-nodemap')
# mark the end of step [3]
FILE_RIGHT_CL_NODEMAP_READ = os.path.join(SYNC_DIR, b'right-nodemap')
# mark that step [9] is read to run
FILE_RIGHT_CL_NODEMAP_PRE_WRITE = os.path.join(
    SYNC_DIR, b'right-pre-nodemap-write'
)
# mark that step [9] has run.
FILE_RIGHT_CL_NODEMAP_POST_WRITE = os.path.join(
    SYNC_DIR, b'right-post-nodemap-write'
)
# mark that step [7] is ready to run
FILE_READER_READY = os.path.join(SYNC_DIR, b'reader-ready')
# mark that step [7] has run
FILE_READER_READ_DOCKET = os.path.join(SYNC_DIR, b'reader-read-docket')


def _print(*args, **kwargs):
    print(*args, **kwargs)


def _role(repo):
    """find the role associated with the process"""
    return repo.ui.config(b'devel', b'nodemap-race.role')


def wrap_changelog_finalize(orig, cl, tr):
    """wrap the update of `00changelog.i` during transaction finalization

    This is useful for synchronisation before or after the file is updated on disk.
    """
    role = getattr(tr, '_race_role', None)
    if role == RIGHT:
        print('right ready to write, waiting for reader')
        testing.wait_file(FILE_READER_READY)
        testing.write_file(FILE_RIGHT_CL_NODEMAP_PRE_WRITE)
        testing.wait_file(FILE_READER_READ_DOCKET)
        print('right proceeding with writing its changelog index and nodemap')
    ret = orig(cl, tr)
    print("finalized changelog write")
    if role == LEFT:
        testing.write_file(FILE_LEFT_CL_DATA_WRITE)
    return ret


def wrap_persist_nodemap(orig, tr, revlog, *args, **kwargs):
    """wrap the update of `00changelog.n` and `*.nd` during tr finalization

    This is useful for synchronisation before or after the files are updated on
    disk.
    """
    is_cl = revlog.target[0] == KIND_CHANGELOG
    role = getattr(tr, '_race_role', None)
    if is_cl:
        if role == LEFT:
            testing.wait_file(FILE_RIGHT_CL_NODEMAP_READ)
    if is_cl:
        print("persisting changelog nodemap")
        print("  new data start at", revlog._nodemap_docket.data_length)
    ret = orig(tr, revlog, *args, **kwargs)
    if is_cl:
        print("persisted changelog nodemap")
        print_nodemap_details(revlog)
        if role == LEFT:
            testing.write_file(FILE_LEFT_CL_NODEMAP_WRITE)
        elif role == RIGHT:
            testing.write_file(FILE_RIGHT_CL_NODEMAP_POST_WRITE)
    return ret


def print_nodemap_details(cl):
    """print relevant information about the nodemap docket currently in memory"""
    dkt = cl._nodemap_docket
    print('docket-details:')
    if dkt is None:
        print('  <no-docket>')
        return
    print('  uid:        ', pycompat.sysstr(dkt.uid))
    print('  actual-tip: ', cl.tiprev())
    print('  tip-rev:    ', dkt.tip_rev)
    print('  data-length:', dkt.data_length)


def wrap_persisted_data(orig, revlog):
    """print some information about the nodemap information we just read

    Used by the <READER> process only.
    """
    ret = orig(revlog)
    if ret is not None:
        docket, data = ret
        file_path = nodemaputil._rawdata_filepath(revlog, docket)
        file_path = revlog.opener.join(file_path)
        file_size = os.path.getsize(file_path)
        print('record-data-length:', docket.data_length)
        print('actual-data-length:', len(data))
        print('file-actual-length:', file_size)
    return ret


def sync_read(orig):
    """used by <READER> to force the race window

    This make sure we read the docker from <LEFT> while reading the datafile
    after <RIGHT> write.
    """
    orig()
    testing.write_file(FILE_READER_READ_DOCKET)
    print('reader: nodemap docket read')
    testing.wait_file(FILE_RIGHT_CL_NODEMAP_POST_WRITE)


def uisetup(ui):
    class RacedRepo(localrepo.localrepository):
        def lock(self, wait=True):
            # make sure <RIGHT> as the "Wrong" information in memory before
            # grabbing the lock
            newlock = self._currentlock(self._lockref) is None
            if newlock and _role(self) == LEFT:
                cl = self.unfiltered().changelog
                print_nodemap_details(cl)
            elif newlock and _role(self) == RIGHT:
                testing.write_file(FILE_RIGHT_READY_TO_LOCK)
                print('nodemap-race: right side start of the locking sequence')
                testing.wait_file(FILE_LEFT_LOCKED)
                testing.wait_file(FILE_LEFT_CL_DATA_WRITE)
                self.invalidate(clearfilecache=True)
                print('nodemap-race: right side reading changelog')
                cl = self.unfiltered().changelog
                tiprev = cl.tiprev()
                tip = cl.node(tiprev)
                tiprev2 = cl.rev(tip)
                if tiprev != tiprev2:
                    raise RuntimeError(
                        'bad tip -round-trip %d %d' % (tiprev, tiprev2)
                    )
                testing.write_file(FILE_RIGHT_CL_NODEMAP_READ)
                print('nodemap-race: right side reading of changelog is done')
                print_nodemap_details(cl)
                testing.wait_file(FILE_LEFT_CL_NODEMAP_WRITE)
                print('nodemap-race: right side ready to wait for the lock')
            ret = super(RacedRepo, self).lock(wait=wait)
            if newlock and _role(self) == LEFT:
                print('nodemap-race: left side locked and ready to commit')
                testing.write_file(FILE_LEFT_LOCKED)
                testing.wait_file(FILE_RIGHT_READY_TO_LOCK)
                cl = self.unfiltered().changelog
                print_nodemap_details(cl)
            elif newlock and _role(self) == RIGHT:
                print('nodemap-race: right side locked and ready to commit')
                cl = self.unfiltered().changelog
                print_nodemap_details(cl)
            return ret

        def transaction(self, *args, **kwargs):
            # duck punch the role on the transaction to help other pieces of code
            tr = super(RacedRepo, self).transaction(*args, **kwargs)
            tr._race_role = _role(self)
            return tr

    localrepo.localrepository = RacedRepo

    extensions.wrapfunction(
        nodemaputil, 'persist_nodemap', wrap_persist_nodemap
    )
    extensions.wrapfunction(
        changelog.changelog, '_finalize', wrap_changelog_finalize
    )


def reposetup(ui, repo):
    if _role(repo) == READER:
        extensions.wrapfunction(
            nodemaputil, 'persisted_data', wrap_persisted_data
        )
        extensions.wrapfunction(nodemaputil, 'test_race_hook_1', sync_read)

        class ReaderRepo(repo.__class__):
            @util.propertycache
            def changelog(self):
                print('reader ready to read the changelog, waiting for right')
                testing.write_file(FILE_READER_READY)
                testing.wait_file(FILE_RIGHT_CL_NODEMAP_PRE_WRITE)
                return super(ReaderRepo, self).changelog

        repo.__class__ = ReaderRepo


@command(b'check-nodemap-race')
def cmd_check_nodemap_race(ui, repo):
    """Run proper <READER> access in the race Windows and check nodemap content"""
    repo = repo.unfiltered()
    print('reader: reading changelog')
    cl = repo.changelog
    print('reader: changelog read')
    print_nodemap_details(cl)
    tip_rev = cl.tiprev()
    tip_node = cl.node(tip_rev)
    print('tip-rev: ', tip_rev)
    print('tip-node:', node.short(tip_node).decode('ascii'))
    print('node-rev:', cl.rev(tip_node))
    for r in cl.revs():
        n = cl.node(r)
        try:
            r2 = cl.rev(n)
        except ValueError as exc:
            print('error while checking revision:', r)
            print(' ', exc)
            return 1
        else:
            if r2 != r:
                print('revision %d is missing from the nodemap' % r)
                return 1
