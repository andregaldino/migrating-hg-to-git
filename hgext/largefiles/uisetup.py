# Copyright 2009-2010 Gregory P. Ward
# Copyright 2009-2010 Intelerad Medical Systems Incorporated
# Copyright 2010-2011 Fog Creek Software
# Copyright 2010-2011 Unity Technologies
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

'''setup for largefiles extension: uisetup'''
from __future__ import absolute_import

from mercurial import (
    cmdutil,
    extensions,
    httppeer,
    sshpeer,
    wireprotov1server,
)

from . import (
    overrides,
    proto,
)

def uisetup(ui):

    cmdutil.outgoinghooks.add('largefiles', overrides.outgoinghook)
    cmdutil.summaryremotehooks.add('largefiles', overrides.summaryremotehook)

    # create the new wireproto commands ...
    wireprotov1server.wireprotocommand('putlfile', 'sha', permission='push')(
        proto.putlfile)
    wireprotov1server.wireprotocommand('getlfile', 'sha', permission='pull')(
        proto.getlfile)
    wireprotov1server.wireprotocommand('statlfile', 'sha', permission='pull')(
        proto.statlfile)
    wireprotov1server.wireprotocommand('lheads', '', permission='pull')(
        wireprotov1server.heads)

    extensions.wrapfunction(wireprotov1server.commands['heads'], 'func',
                            proto.heads)
    # TODO also wrap wireproto.commandsv2 once heads is implemented there.

    # can't do this in reposetup because it needs to have happened before
    # wirerepo.__init__ is called
    proto.ssholdcallstream = sshpeer.sshv1peer._callstream
    proto.httpoldcallstream = httppeer.httppeer._callstream
    sshpeer.sshv1peer._callstream = proto.sshrepocallstream
    httppeer.httppeer._callstream = proto.httprepocallstream

    # override some extensions' stuff as well
    for name, module in extensions.extensions():
        if name == 'rebase':
            # TODO: teach exthelper to handle this
            extensions.wrapfunction(module, 'rebase',
                                    overrides.overriderebase)
