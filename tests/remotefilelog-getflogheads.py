from mercurial.i18n import _
from mercurial import (
    hg,
    registrar,
)
from mercurial.utils import (
    urlutil,
)

cmdtable = {}
command = registrar.command(cmdtable)


@command(b'getflogheads', [], b'path')
def getflogheads(ui, repo, path):
    """
    Extension printing a remotefilelog's heads

    Used for testing purpose
    """

    dest = urlutil.get_unique_pull_path(b'getflogheads', repo, ui)[0]
    peer = hg.peer(repo, {}, dest)

    try:
        flogheads = peer.x_rfl_getflogheads(path)
    finally:
        peer.close()

    if flogheads:
        for head in flogheads:
            ui.write(head + b'\n')
    else:
        ui.write(_(b'EMPTY\n'))
