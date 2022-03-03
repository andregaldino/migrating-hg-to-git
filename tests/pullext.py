# pullext.py - Simple extension to test pulling
#
# Copyright 2018 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.


from mercurial.i18n import _
from mercurial import (
    commands,
    error,
    extensions,
    localrepo,
    requirements,
)


def clonecommand(orig, ui, repo, *args, **kwargs):
    if kwargs.get('include') or kwargs.get('exclude'):
        kwargs['narrow'] = True

    if kwargs.get('depth'):
        try:
            kwargs['depth'] = int(kwargs['depth'])
        except ValueError:
            raise error.Abort(_('--depth must be an integer'))

    return orig(ui, repo, *args, **kwargs)


def featuresetup(ui, features):
    features.add(requirements.NARROW_REQUIREMENT)


def extsetup(ui):
    entry = extensions.wrapcommand(commands.table, b'clone', clonecommand)

    hasinclude = any(x[1] == b'include' for x in entry[1])
    hasdepth = any(x[1] == b'depth' for x in entry[1])

    if not hasinclude:
        entry[1].append(
            (b'', b'include', [], _(b'pattern of file/directory to clone'))
        )
        entry[1].append(
            (b'', b'exclude', [], _(b'pattern of file/directory to not clone'))
        )

    if not hasdepth:
        entry[1].append(
            (b'', b'depth', b'', _(b'ancestry depth of changesets to fetch'))
        )

    localrepo.featuresetupfuncs.add(featuresetup)
