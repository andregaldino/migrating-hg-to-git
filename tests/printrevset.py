from mercurial.thirdparty import attr
from mercurial import (
    cmdutil,
    commands,
    extensions,
    logcmdutil,
    revsetlang,
    smartset,
)

from mercurial.utils import stringutil


def logrevset(repo, wopts):
    revs = logcmdutil._initialrevs(repo, wopts)
    if not revs:
        return None
    match, pats, slowpath = logcmdutil._makematcher(repo, revs, wopts)
    wopts = attr.evolve(wopts, pats=pats)
    return logcmdutil._makerevset(repo, wopts, slowpath)


def uisetup(ui):
    def printrevset(orig, repo, wopts):
        revs, filematcher = orig(repo, wopts)
        if wopts.opts.get(b'print_revset'):
            expr = logrevset(repo, wopts)
            if expr:
                tree = revsetlang.parse(expr)
                tree = revsetlang.analyze(tree)
            else:
                tree = []
            ui = repo.ui
            ui.write(b'%s\n' % stringutil.pprint(wopts.opts.get(b'rev', [])))
            ui.write(revsetlang.prettyformat(tree) + b'\n')
            ui.write(stringutil.prettyrepr(revs) + b'\n')
            revs = smartset.baseset()  # display no revisions
        return revs, filematcher

    extensions.wrapfunction(logcmdutil, 'getrevs', printrevset)
    aliases, entry = cmdutil.findcmd(b'log', commands.table)
    entry[1].append(
        (
            b'',
            b'print-revset',
            False,
            b'print generated revset and exit (DEPRECATED)',
        )
    )
