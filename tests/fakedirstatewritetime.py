# extension to emulate invoking 'dirstate.write()' at the time
# specified by '[fakedirstatewritetime] fakenow', only when
# 'dirstate.write()' is invoked via functions below:
#
#   - 'workingctx._poststatusfixup()' (= 'repo.status()')
#   - 'committablectx.markcommitted()'


from mercurial import (
    context,
    dirstatemap as dirstatemapmod,
    extensions,
    policy,
    registrar,
)
from mercurial.dirstateutils import timestamp
from mercurial.utils import dateutil

try:
    from mercurial import rustext

    rustext.__name__  # force actual import (see hgdemandimport)
except ImportError:
    rustext = None

configtable = {}
configitem = registrar.configitem(configtable)

configitem(
    b'fakedirstatewritetime',
    b'fakenow',
    default=None,
)

parsers = policy.importmod('parsers')
has_rust_dirstate = policy.importrust('dirstate') is not None


def pack_dirstate(orig, dmap, copymap, pl):
    return orig(dmap, copymap, pl)


def fakewrite(ui, func):
    # fake "now" of 'pack_dirstate' only if it is invoked while 'func'

    fakenow = ui.config(b'fakedirstatewritetime', b'fakenow')
    if not fakenow:
        # Execute original one, if fakenow isn't configured. This is
        # useful to prevent subrepos from executing replaced one,
        # because replacing 'parsers.pack_dirstate' is also effective
        # in subrepos.
        return func()

    # parsing 'fakenow' in YYYYmmddHHMM format makes comparison between
    # 'fakenow' value and 'touch -t YYYYmmddHHMM' argument easy
    fakenow = dateutil.parsedate(fakenow, [b'%Y%m%d%H%M'])[0]
    fakenow = timestamp.timestamp((fakenow, 0, False))

    if has_rust_dirstate:
        # The Rust implementation does not use public parse/pack dirstate
        # to prevent conversion round-trips
        orig_dirstatemap_write = dirstatemapmod.dirstatemap.write
        wrapper = lambda self, tr, st: orig_dirstatemap_write(self, tr, st)
        dirstatemapmod.dirstatemap.write = wrapper

    orig_get_fs_now = timestamp.get_fs_now
    wrapper = lambda *args: pack_dirstate(orig_pack_dirstate, *args)

    orig_module = parsers
    orig_pack_dirstate = parsers.pack_dirstate

    orig_module.pack_dirstate = wrapper
    timestamp.get_fs_now = (
        lambda *args: fakenow
    )  # XXX useless for this purpose now
    try:
        return func()
    finally:
        orig_module.pack_dirstate = orig_pack_dirstate
        timestamp.get_fs_now = orig_get_fs_now
        if has_rust_dirstate:
            dirstatemapmod.dirstatemap.write = orig_dirstatemap_write


def _poststatusfixup(orig, workingctx, status, fixup):
    ui = workingctx.repo().ui
    return fakewrite(ui, lambda: orig(workingctx, status, fixup))


def markcommitted(orig, committablectx, node):
    ui = committablectx.repo().ui
    return fakewrite(ui, lambda: orig(committablectx, node))


def extsetup(ui):
    extensions.wrapfunction(
        context.workingctx, '_poststatusfixup', _poststatusfixup
    )
    extensions.wrapfunction(context.workingctx, 'markcommitted', markcommitted)
