# extension to emulate interrupting filemerge._filemerge

from __future__ import absolute_import

from mercurial import (
    error,
    extensions,
    filemerge,
)


def failfilemerge(*args, **kwargs):
    raise error.Abort(b"^C")


def extsetup(ui):
    extensions.wrapfunction(filemerge, 'filemerge', failfilemerge)
