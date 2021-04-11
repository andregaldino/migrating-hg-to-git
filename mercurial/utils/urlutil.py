# utils.urlutil - code related to [paths] management
#
# Copyright 2005-2021 Olivia Mackall <olivia@selenic.com> and others
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.
import os

from ..i18n import _
from ..pycompat import (
    getattr,
    setattr,
)
from .. import (
    error,
    pycompat,
    util,
)


class paths(dict):
    """Represents a collection of paths and their configs.

    Data is initially derived from ui instances and the config files they have
    loaded.
    """

    def __init__(self, ui):
        dict.__init__(self)

        for name, loc in ui.configitems(b'paths', ignoresub=True):
            # No location is the same as not existing.
            if not loc:
                continue
            loc, sub_opts = ui.configsuboptions(b'paths', name)
            self[name] = path(ui, name, rawloc=loc, suboptions=sub_opts)

        for name, p in sorted(self.items()):
            p.chain_path(ui, self)

    def getpath(self, ui, name, default=None):
        """Return a ``path`` from a string, falling back to default.

        ``name`` can be a named path or locations. Locations are filesystem
        paths or URIs.

        Returns None if ``name`` is not a registered path, a URI, or a local
        path to a repo.
        """
        # Only fall back to default if no path was requested.
        if name is None:
            if not default:
                default = ()
            elif not isinstance(default, (tuple, list)):
                default = (default,)
            for k in default:
                try:
                    return self[k]
                except KeyError:
                    continue
            return None

        # Most likely empty string.
        # This may need to raise in the future.
        if not name:
            return None

        try:
            return self[name]
        except KeyError:
            # Try to resolve as a local path or URI.
            try:
                # we pass the ui instance are warning might need to be issued
                return path(ui, None, rawloc=name)
            except ValueError:
                raise error.RepoError(_(b'repository %s does not exist') % name)


_pathsuboptions = {}


def pathsuboption(option, attr):
    """Decorator used to declare a path sub-option.

    Arguments are the sub-option name and the attribute it should set on
    ``path`` instances.

    The decorated function will receive as arguments a ``ui`` instance,
    ``path`` instance, and the string value of this option from the config.
    The function should return the value that will be set on the ``path``
    instance.

    This decorator can be used to perform additional verification of
    sub-options and to change the type of sub-options.
    """

    def register(func):
        _pathsuboptions[option] = (attr, func)
        return func

    return register


@pathsuboption(b'pushurl', b'pushloc')
def pushurlpathoption(ui, path, value):
    u = util.url(value)
    # Actually require a URL.
    if not u.scheme:
        ui.warn(_(b'(paths.%s:pushurl not a URL; ignoring)\n') % path.name)
        return None

    # Don't support the #foo syntax in the push URL to declare branch to
    # push.
    if u.fragment:
        ui.warn(
            _(
                b'("#fragment" in paths.%s:pushurl not supported; '
                b'ignoring)\n'
            )
            % path.name
        )
        u.fragment = None

    return bytes(u)


@pathsuboption(b'pushrev', b'pushrev')
def pushrevpathoption(ui, path, value):
    return value


class path(object):
    """Represents an individual path and its configuration."""

    def __init__(self, ui, name, rawloc=None, suboptions=None):
        """Construct a path from its config options.

        ``ui`` is the ``ui`` instance the path is coming from.
        ``name`` is the symbolic name of the path.
        ``rawloc`` is the raw location, as defined in the config.
        ``pushloc`` is the raw locations pushes should be made to.

        If ``name`` is not defined, we require that the location be a) a local
        filesystem path with a .hg directory or b) a URL. If not,
        ``ValueError`` is raised.
        """
        if not rawloc:
            raise ValueError(b'rawloc must be defined')

        # Locations may define branches via syntax <base>#<branch>.
        u = util.url(rawloc)
        branch = None
        if u.fragment:
            branch = u.fragment
            u.fragment = None

        self.url = u
        # the url from the config/command line before dealing with `path://`
        self.raw_url = u.copy()
        self.branch = branch

        self.name = name
        self.rawloc = rawloc
        self.loc = b'%s' % u

        self._validate_path()

        _path, sub_opts = ui.configsuboptions(b'paths', b'*')
        self._own_sub_opts = {}
        if suboptions is not None:
            self._own_sub_opts = suboptions.copy()
            sub_opts.update(suboptions)
        self._all_sub_opts = sub_opts.copy()

        self._apply_suboptions(ui, sub_opts)

    def chain_path(self, ui, paths):
        if self.url.scheme == b'path':
            assert self.url.path is None
            try:
                subpath = paths[self.url.host]
            except KeyError:
                m = _('cannot use `%s`, "%s" is not a known path')
                m %= (self.rawloc, self.url.host)
                raise error.Abort(m)
            if subpath.raw_url.scheme == b'path':
                m = _('cannot use `%s`, "%s" is also define as a `path://`')
                m %= (self.rawloc, self.url.host)
                raise error.Abort(m)
            self.url = subpath.url
            self.rawloc = subpath.rawloc
            self.loc = subpath.loc
            if self.branch is None:
                self.branch = subpath.branch
            else:
                base = self.rawloc.rsplit(b'#', 1)[0]
                self.rawloc = b'%s#%s' % (base, self.branch)
            suboptions = subpath._all_sub_opts.copy()
            suboptions.update(self._own_sub_opts)
            self._apply_suboptions(ui, suboptions)

    def _validate_path(self):
        # When given a raw location but not a symbolic name, validate the
        # location is valid.
        if (
            not self.name
            and not self.url.scheme
            and not self._isvalidlocalpath(self.loc)
        ):
            raise ValueError(
                b'location is not a URL or path to a local '
                b'repo: %s' % self.rawloc
            )

    def _apply_suboptions(self, ui, sub_options):
        # Now process the sub-options. If a sub-option is registered, its
        # attribute will always be present. The value will be None if there
        # was no valid sub-option.
        for suboption, (attr, func) in pycompat.iteritems(_pathsuboptions):
            if suboption not in sub_options:
                setattr(self, attr, None)
                continue

            value = func(ui, self, sub_options[suboption])
            setattr(self, attr, value)

    def _isvalidlocalpath(self, path):
        """Returns True if the given path is a potentially valid repository.
        This is its own function so that extensions can change the definition of
        'valid' in this case (like when pulling from a git repo into a hg
        one)."""
        try:
            return os.path.isdir(os.path.join(path, b'.hg'))
        # Python 2 may return TypeError. Python 3, ValueError.
        except (TypeError, ValueError):
            return False

    @property
    def suboptions(self):
        """Return sub-options and their values for this path.

        This is intended to be used for presentation purposes.
        """
        d = {}
        for subopt, (attr, _func) in pycompat.iteritems(_pathsuboptions):
            value = getattr(self, attr)
            if value is not None:
                d[subopt] = value
        return d
