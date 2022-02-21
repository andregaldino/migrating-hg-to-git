# Test that certain objects conform to well-defined interfaces.


from mercurial import encoding

encoding.environ[b'HGREALINTERFACES'] = b'1'

import os
import subprocess
import sys

# Only run if tests are run in a repo
if subprocess.call(
    [sys.executable, '%s/hghave' % os.environ['TESTDIR'], 'test-repo']
):
    sys.exit(80)

from mercurial.interfaces import (
    dirstate as intdirstate,
    repository,
)
from mercurial.thirdparty.zope import interface as zi
from mercurial.thirdparty.zope.interface import verify as ziverify
from mercurial import (
    bundlerepo,
    dirstate,
    filelog,
    httppeer,
    localrepo,
    manifest,
    pycompat,
    revlog,
    sshpeer,
    statichttprepo,
    ui as uimod,
    unionrepo,
    vfs as vfsmod,
    wireprotoserver,
    wireprototypes,
    wireprotov1peer,
)

testdir = os.path.dirname(__file__)
rootdir = pycompat.fsencode(os.path.normpath(os.path.join(testdir, '..')))

sys.path[0:0] = [testdir]
import simplestorerepo

del sys.path[0]


def checkzobject(o, allowextra=False):
    """Verify an object with a zope interface."""
    ifaces = zi.providedBy(o)
    if not ifaces:
        print('%r does not provide any zope interfaces' % o)
        return

    # Run zope.interface's built-in verification routine. This verifies that
    # everything that is supposed to be present is present.
    for iface in ifaces:
        ziverify.verifyObject(iface, o)

    if allowextra:
        return

    # Now verify that the object provides no extra public attributes that
    # aren't declared as part of interfaces.
    allowed = set()
    for iface in ifaces:
        allowed |= set(iface.names(all=True))

    public = {a for a in dir(o) if not a.startswith('_')}

    for attr in sorted(public - allowed):
        print(
            'public attribute not declared in interfaces: %s.%s'
            % (o.__class__.__name__, attr)
        )


# Facilitates testing localpeer.
class dummyrepo:
    def __init__(self):
        self.ui = uimod.ui()
        self._wanted_sidedata = set()

    def filtered(self, name):
        pass

    def _restrictcapabilities(self, caps):
        pass


class dummyopener:
    handlers = []


# Facilitates testing sshpeer without requiring a server.
class badpeer(httppeer.httppeer):
    def __init__(self):
        super(badpeer, self).__init__(
            None, None, None, dummyopener(), None, None
        )
        self.badattribute = True

    def badmethod(self):
        pass


class dummypipe:
    def close(self):
        pass

    @property
    def closed(self):
        pass


def main():
    ui = uimod.ui()
    # Needed so we can open a local repo with obsstore without a warning.
    ui.setconfig(b'experimental', b'evolution.createmarkers', True)

    checkzobject(badpeer())

    ziverify.verifyClass(repository.ipeerbase, httppeer.httppeer)
    checkzobject(httppeer.httppeer(None, None, None, dummyopener(), None, None))

    ziverify.verifyClass(repository.ipeerbase, localrepo.localpeer)
    checkzobject(localrepo.localpeer(dummyrepo()))

    ziverify.verifyClass(
        repository.ipeercommandexecutor, localrepo.localcommandexecutor
    )
    checkzobject(localrepo.localcommandexecutor(None))

    ziverify.verifyClass(
        repository.ipeercommandexecutor, wireprotov1peer.peerexecutor
    )
    checkzobject(wireprotov1peer.peerexecutor(None))

    ziverify.verifyClass(repository.ipeerbase, sshpeer.sshv1peer)
    checkzobject(
        sshpeer.sshv1peer(
            ui,
            b'ssh://localhost/foo',
            b'',
            dummypipe(),
            dummypipe(),
            None,
            None,
        )
    )

    ziverify.verifyClass(repository.ipeerbase, bundlerepo.bundlepeer)
    checkzobject(bundlerepo.bundlepeer(dummyrepo()))

    ziverify.verifyClass(repository.ipeerbase, statichttprepo.statichttppeer)
    checkzobject(statichttprepo.statichttppeer(dummyrepo()))

    ziverify.verifyClass(repository.ipeerbase, unionrepo.unionpeer)
    checkzobject(unionrepo.unionpeer(dummyrepo()))

    ziverify.verifyClass(
        repository.ilocalrepositorymain, localrepo.localrepository
    )
    ziverify.verifyClass(
        repository.ilocalrepositoryfilestorage, localrepo.revlogfilestorage
    )
    repo = localrepo.makelocalrepository(ui, rootdir)
    checkzobject(repo)

    ziverify.verifyClass(
        wireprototypes.baseprotocolhandler, wireprotoserver.sshv1protocolhandler
    )
    ziverify.verifyClass(
        wireprototypes.baseprotocolhandler,
        wireprotoserver.httpv1protocolhandler,
    )

    sshv1 = wireprotoserver.sshv1protocolhandler(None, None, None)
    checkzobject(sshv1)

    httpv1 = wireprotoserver.httpv1protocolhandler(None, None, None)
    checkzobject(httpv1)

    ziverify.verifyClass(repository.ifilestorage, filelog.filelog)
    ziverify.verifyClass(repository.imanifestdict, manifest.manifestdict)
    ziverify.verifyClass(repository.imanifestdict, manifest.treemanifest)
    ziverify.verifyClass(
        repository.imanifestrevisionstored, manifest.manifestctx
    )
    ziverify.verifyClass(
        repository.imanifestrevisionwritable, manifest.memmanifestctx
    )
    ziverify.verifyClass(
        repository.imanifestrevisionstored, manifest.treemanifestctx
    )
    ziverify.verifyClass(
        repository.imanifestrevisionwritable, manifest.memtreemanifestctx
    )
    ziverify.verifyClass(repository.imanifestlog, manifest.manifestlog)
    ziverify.verifyClass(repository.imanifeststorage, manifest.manifestrevlog)

    ziverify.verifyClass(
        repository.irevisiondelta, simplestorerepo.simplestorerevisiondelta
    )
    ziverify.verifyClass(repository.ifilestorage, simplestorerepo.filestorage)
    ziverify.verifyClass(
        repository.iverifyproblem, simplestorerepo.simplefilestoreproblem
    )

    ziverify.verifyClass(intdirstate.idirstate, dirstate.dirstate)

    vfs = vfsmod.vfs(b'.')
    fl = filelog.filelog(vfs, b'dummy.i')
    checkzobject(fl, allowextra=True)

    # Conforms to imanifestlog.
    ml = manifest.manifestlog(
        vfs,
        repo,
        manifest.manifestrevlog(repo.nodeconstants, repo.svfs),
        repo.narrowmatch(),
    )
    checkzobject(ml)
    checkzobject(repo.manifestlog)

    # Conforms to imanifestrevision.
    mctx = ml[repo[0].manifestnode()]
    checkzobject(mctx)

    # Conforms to imanifestrevisionwritable.
    checkzobject(mctx.copy())

    # Conforms to imanifestdict.
    checkzobject(mctx.read())

    mrl = manifest.manifestrevlog(repo.nodeconstants, vfs)
    checkzobject(mrl)

    ziverify.verifyClass(repository.irevisiondelta, revlog.revlogrevisiondelta)

    rd = revlog.revlogrevisiondelta(
        node=b'',
        p1node=b'',
        p2node=b'',
        basenode=b'',
        linknode=b'',
        flags=b'',
        baserevisionsize=None,
        revision=b'',
        sidedata=b'',
        delta=None,
        protocol_flags=b'',
    )
    checkzobject(rd)

    ziverify.verifyClass(repository.iverifyproblem, revlog.revlogproblem)
    checkzobject(revlog.revlogproblem())


main()
