# Copyright 2009-2010 Gregory P. Ward
# Copyright 2009-2010 Intelerad Medical Systems Incorporated
# Copyright 2010-2011 Fog Creek Software
# Copyright 2010-2011 Unity Technologies
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

'''setup for largefiles extension: uisetup'''
from __future__ import absolute_import

from mercurial.hgweb import (
    webcommands,
)

from mercurial import (
    archival,
    cmdutil,
    copies,
    exchange,
    extensions,
    filemerge,
    hg,
    httppeer,
    merge,
    scmutil,
    sshpeer,
    subrepo,
    upgrade,
    url,
    wireprotov1server,
)

from . import (
    overrides,
    proto,
)

def uisetup(ui):
    # Disable auto-status for some commands which assume that all
    # files in the result are under Mercurial's control

    # The scmutil function is called both by the (trivial) addremove command,
    # and in the process of handling commit -A (issue3542)
    extensions.wrapfunction(scmutil, 'addremove', overrides.scmutiladdremove)
    extensions.wrapfunction(cmdutil, 'add', overrides.cmdutiladd)
    extensions.wrapfunction(cmdutil, 'remove', overrides.cmdutilremove)
    extensions.wrapfunction(cmdutil, 'forget', overrides.cmdutilforget)

    extensions.wrapfunction(copies, 'pathcopies', overrides.copiespathcopies)

    extensions.wrapfunction(upgrade, 'preservedrequirements',
                            overrides.upgraderequirements)

    extensions.wrapfunction(upgrade, 'supporteddestrequirements',
                            overrides.upgraderequirements)

    # Subrepos call status function
    extensions.wrapfunction(subrepo.hgsubrepo, 'status',
                            overrides.overridestatusfn)

    cmdutil.outgoinghooks.add('largefiles', overrides.outgoinghook)
    cmdutil.summaryremotehooks.add('largefiles', overrides.summaryremotehook)

    extensions.wrapfunction(exchange, 'pushoperation',
                            overrides.exchangepushoperation)

    extensions.wrapfunction(hg, 'clone', overrides.hgclone)

    extensions.wrapfunction(merge, '_checkunknownfile',
                            overrides.overridecheckunknownfile)
    extensions.wrapfunction(merge, 'calculateupdates',
                            overrides.overridecalculateupdates)
    extensions.wrapfunction(merge, 'recordupdates',
                            overrides.mergerecordupdates)
    extensions.wrapfunction(merge, 'update', overrides.mergeupdate)
    extensions.wrapfunction(filemerge, '_filemerge',
                            overrides.overridefilemerge)
    extensions.wrapfunction(cmdutil, 'copy', overrides.overridecopy)

    # Summary calls dirty on the subrepos
    extensions.wrapfunction(subrepo.hgsubrepo, 'dirty', overrides.overridedirty)

    extensions.wrapfunction(cmdutil, 'revert', overrides.overriderevert)

    extensions.wrapfunction(archival, 'archive', overrides.overridearchive)
    extensions.wrapfunction(subrepo.hgsubrepo, 'archive',
                            overrides.hgsubrepoarchive)
    extensions.wrapfunction(webcommands, 'archive', overrides.hgwebarchive)
    extensions.wrapfunction(cmdutil, 'bailifchanged',
                            overrides.overridebailifchanged)

    extensions.wrapfunction(cmdutil, 'postcommitstatus',
                            overrides.postcommitstatus)
    extensions.wrapfunction(scmutil, 'marktouched',
                            overrides.scmutilmarktouched)

    extensions.wrapfunction(url, 'open',
                            overrides.openlargefile)

    # create the new wireproto commands ...
    wireprotov1server.wireprotocommand('putlfile', 'sha', permission='push')(
        proto.putlfile)
    wireprotov1server.wireprotocommand('getlfile', 'sha', permission='pull')(
        proto.getlfile)
    wireprotov1server.wireprotocommand('statlfile', 'sha', permission='pull')(
        proto.statlfile)
    wireprotov1server.wireprotocommand('lheads', '', permission='pull')(
        wireprotov1server.heads)

    # ... and wrap some existing ones
    extensions.wrapfunction(wireprotov1server.commands['heads'], 'func',
                            proto.heads)
    # TODO also wrap wireproto.commandsv2 once heads is implemented there.

    extensions.wrapfunction(webcommands, 'decodepath', overrides.decodepath)

    extensions.wrapfunction(wireprotov1server, '_capabilities',
                            proto._capabilities)

    # can't do this in reposetup because it needs to have happened before
    # wirerepo.__init__ is called
    proto.ssholdcallstream = sshpeer.sshv1peer._callstream
    proto.httpoldcallstream = httppeer.httppeer._callstream
    sshpeer.sshv1peer._callstream = proto.sshrepocallstream
    httppeer.httppeer._callstream = proto.httprepocallstream

    # override some extensions' stuff as well
    for name, module in extensions.extensions():
        if name == 'rebase':
            extensions.wrapfunction(module, 'rebase',
                                    overrides.overriderebase)
