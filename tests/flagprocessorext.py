# coding=UTF-8


import base64
import zlib

from mercurial import (
    bundlecaches,
    changegroup,
    extensions,
    revlog,
    util,
)
from mercurial.revlogutils import flagutil
from mercurial.interfaces import repository

# Test only: These flags are defined here only in the context of testing the
# behavior of the flag processor. The canonical way to add flags is to get in
# touch with the community and make them known in revlog.
REVIDX_NOOP = 1 << 3
REVIDX_BASE64 = 1 << 2
REVIDX_GZIP = 1 << 1
REVIDX_FAIL = 1


def validatehash(self, text):
    return True


def bypass(self, text):
    return False


def noopdonothing(self, text):
    return (text, True)


def noopdonothingread(self, text):
    return (text, True)


def b64encode(self, text):
    return (base64.b64encode(text), False)


def b64decode(self, text):
    return (base64.b64decode(text), True)


def gzipcompress(self, text):
    return (zlib.compress(text), False)


def gzipdecompress(self, text):
    return (zlib.decompress(text), True)


def supportedoutgoingversions(orig, repo):
    versions = orig(repo)
    versions.discard(b'01')
    versions.discard(b'02')
    versions.add(b'03')
    return versions


def allsupportedversions(orig, ui):
    versions = orig(ui)
    versions.add(b'03')
    return versions


def makewrappedfile(obj):
    class wrappedfile(obj.__class__):
        def addrevision(
            self,
            text,
            transaction,
            link,
            p1,
            p2,
            cachedelta=None,
            node=None,
            flags=flagutil.REVIDX_DEFAULT_FLAGS,
        ):
            if b'[NOOP]' in text:
                flags |= REVIDX_NOOP

            if b'[BASE64]' in text:
                flags |= REVIDX_BASE64

            if b'[GZIP]' in text:
                flags |= REVIDX_GZIP

            # This addrevision wrapper is meant to add a flag we will not have
            # transforms registered for, ensuring we handle this error case.
            if b'[FAIL]' in text:
                flags |= REVIDX_FAIL

            return super(wrappedfile, self).addrevision(
                text,
                transaction,
                link,
                p1,
                p2,
                cachedelta=cachedelta,
                node=node,
                flags=flags,
            )

    obj.__class__ = wrappedfile


def reposetup(ui, repo):
    class wrappingflagprocessorrepo(repo.__class__):
        def file(self, f):
            orig = super(wrappingflagprocessorrepo, self).file(f)
            makewrappedfile(orig)
            return orig

    repo.__class__ = wrappingflagprocessorrepo


def extsetup(ui):
    # Enable changegroup3 for flags to be sent over the wire
    wrapfunction = extensions.wrapfunction
    wrapfunction(
        changegroup, 'supportedoutgoingversions', supportedoutgoingversions
    )
    wrapfunction(changegroup, 'allsupportedversions', allsupportedversions)

    # Teach revlog about our test flags
    flags = [REVIDX_NOOP, REVIDX_BASE64, REVIDX_GZIP, REVIDX_FAIL]
    flagutil.REVIDX_KNOWN_FLAGS |= util.bitsfrom(flags)
    repository.REVISION_FLAGS_KNOWN |= util.bitsfrom(flags)
    revlog.REVIDX_FLAGS_ORDER.extend(flags)

    # Teach exchange to use changegroup 3
    for k in bundlecaches._bundlespeccontentopts.keys():
        bundlecaches._bundlespeccontentopts[k][b"cg.version"] = b"03"

    # Register flag processors for each extension
    flagutil.addflagprocessor(
        REVIDX_NOOP,
        (
            noopdonothingread,
            noopdonothing,
            validatehash,
        ),
    )
    flagutil.addflagprocessor(
        REVIDX_BASE64,
        (
            b64decode,
            b64encode,
            bypass,
        ),
    )
    flagutil.addflagprocessor(
        REVIDX_GZIP, (gzipdecompress, gzipcompress, bypass)
    )
