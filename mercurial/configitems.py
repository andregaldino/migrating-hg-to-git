# configitems.py - centralized declaration of configuration option
#
#  Copyright 2017 Pierre-Yves David <pierre-yves.david@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import functools
import re

from . import (
    encoding,
    error,
)


def loadconfigtable(ui, extname, configtable):
    """update config item known to the ui with the extension ones"""
    for section, items in sorted(configtable.items()):
        knownitems = ui._knownconfig.setdefault(section, itemregister())
        knownkeys = set(knownitems)
        newkeys = set(items)
        for key in sorted(knownkeys & newkeys):
            msg = b"extension '%s' overwrite config item '%s.%s'"
            msg %= (extname, section, key)
            ui.develwarn(msg, config=b'warn-config')

        knownitems.update(items)


class configitem(object):
    """represent a known config item

    :section: the official config section where to find this item,
       :name: the official name within the section,
    :default: default value for this item,
    :alias: optional list of tuples as alternatives,
    :generic: this is a generic definition, match name using regular expression.
    """

    def __init__(
        self,
        section,
        name,
        default=None,
        alias=(),
        generic=False,
        priority=0,
        experimental=False,
    ):
        self.section = section
        self.name = name
        self.default = default
        self.alias = list(alias)
        self.generic = generic
        self.priority = priority
        self.experimental = experimental
        self._re = None
        if generic:
            self._re = re.compile(self.name)


class itemregister(dict):
    """A specialized dictionary that can handle wild-card selection"""

    def __init__(self):
        super(itemregister, self).__init__()
        self._generics = set()

    def update(self, other):
        super(itemregister, self).update(other)
        self._generics.update(other._generics)

    def __setitem__(self, key, item):
        super(itemregister, self).__setitem__(key, item)
        if item.generic:
            self._generics.add(item)

    def get(self, key):
        baseitem = super(itemregister, self).get(key)
        if baseitem is not None and not baseitem.generic:
            return baseitem

        # search for a matching generic item
        generics = sorted(self._generics, key=(lambda x: (x.priority, x.name)))
        for item in generics:
            # we use 'match' instead of 'search' to make the matching simpler
            # for people unfamiliar with regular expression. Having the match
            # rooted to the start of the string will produce less surprising
            # result for user writing simple regex for sub-attribute.
            #
            # For example using "color\..*" match produces an unsurprising
            # result, while using search could suddenly match apparently
            # unrelated configuration that happens to contains "color."
            # anywhere. This is a tradeoff where we favor requiring ".*" on
            # some match to avoid the need to prefix most pattern with "^".
            # The "^" seems more error prone.
            if item._re.match(key):
                return item

        return None


coreitems = {}


def _register(configtable, *args, **kwargs):
    item = configitem(*args, **kwargs)
    section = configtable.setdefault(item.section, itemregister())
    if item.name in section:
        msg = b"duplicated config item registration for '%s.%s'"
        raise error.ProgrammingError(msg % (item.section, item.name))
    section[item.name] = item


# special value for case where the default is derived from other values
dynamicdefault = object()

# Registering actual config items


def getitemregister(configtable):
    f = functools.partial(_register, configtable)
    # export pseudo enum as configitem.*
    f.dynamicdefault = dynamicdefault
    return f


coreconfigitem = getitemregister(coreitems)


def _registerdiffopts(section, configprefix=b''):
    coreconfigitem(
        section, configprefix + b'nodates', default=False,
    )
    coreconfigitem(
        section, configprefix + b'showfunc', default=False,
    )
    coreconfigitem(
        section, configprefix + b'unified', default=None,
    )
    coreconfigitem(
        section, configprefix + b'git', default=False,
    )
    coreconfigitem(
        section, configprefix + b'ignorews', default=False,
    )
    coreconfigitem(
        section, configprefix + b'ignorewsamount', default=False,
    )
    coreconfigitem(
        section, configprefix + b'ignoreblanklines', default=False,
    )
    coreconfigitem(
        section, configprefix + b'ignorewseol', default=False,
    )
    coreconfigitem(
        section, configprefix + b'nobinary', default=False,
    )
    coreconfigitem(
        section, configprefix + b'noprefix', default=False,
    )
    coreconfigitem(
        section, configprefix + b'word-diff', default=False,
    )


coreconfigitem(
    b'alias', b'.*', default=dynamicdefault, generic=True,
)
coreconfigitem(
    b'auth', b'cookiefile', default=None,
)
_registerdiffopts(section=b'annotate')
# bookmarks.pushing: internal hack for discovery
coreconfigitem(
    b'bookmarks', b'pushing', default=list,
)
# bundle.mainreporoot: internal hack for bundlerepo
coreconfigitem(
    b'bundle', b'mainreporoot', default=b'',
)
coreconfigitem(
    b'censor', b'policy', default=b'abort', experimental=True,
)
coreconfigitem(
    b'chgserver', b'idletimeout', default=3600,
)
coreconfigitem(
    b'chgserver', b'skiphash', default=False,
)
coreconfigitem(
    b'cmdserver', b'log', default=None,
)
coreconfigitem(
    b'cmdserver', b'max-log-files', default=7,
)
coreconfigitem(
    b'cmdserver', b'max-log-size', default=b'1 MB',
)
coreconfigitem(
    b'cmdserver', b'max-repo-cache', default=0, experimental=True,
)
coreconfigitem(
    b'cmdserver', b'message-encodings', default=list, experimental=True,
)
coreconfigitem(
    b'cmdserver',
    b'track-log',
    default=lambda: [b'chgserver', b'cmdserver', b'repocache'],
)
coreconfigitem(
    b'color', b'.*', default=None, generic=True,
)
coreconfigitem(
    b'color', b'mode', default=b'auto',
)
coreconfigitem(
    b'color', b'pagermode', default=dynamicdefault,
)
_registerdiffopts(section=b'commands', configprefix=b'commit.interactive.')
coreconfigitem(
    b'commands', b'commit.post-status', default=False,
)
coreconfigitem(
    b'commands', b'grep.all-files', default=False, experimental=True,
)
coreconfigitem(
    b'commands', b'merge.require-rev', default=False,
)
coreconfigitem(
    b'commands', b'push.require-revs', default=False,
)
coreconfigitem(
    b'commands', b'resolve.confirm', default=False,
)
coreconfigitem(
    b'commands', b'resolve.explicit-re-merge', default=False,
)
coreconfigitem(
    b'commands', b'resolve.mark-check', default=b'none',
)
_registerdiffopts(section=b'commands', configprefix=b'revert.interactive.')
coreconfigitem(
    b'commands', b'show.aliasprefix', default=list,
)
coreconfigitem(
    b'commands', b'status.relative', default=False,
)
coreconfigitem(
    b'commands', b'status.skipstates', default=[], experimental=True,
)
coreconfigitem(
    b'commands', b'status.terse', default=b'',
)
coreconfigitem(
    b'commands', b'status.verbose', default=False,
)
coreconfigitem(
    b'commands', b'update.check', default=None,
)
coreconfigitem(
    b'commands', b'update.requiredest', default=False,
)
coreconfigitem(
    b'committemplate', b'.*', default=None, generic=True,
)
coreconfigitem(
    b'convert', b'bzr.saverev', default=True,
)
coreconfigitem(
    b'convert', b'cvsps.cache', default=True,
)
coreconfigitem(
    b'convert', b'cvsps.fuzz', default=60,
)
coreconfigitem(
    b'convert', b'cvsps.logencoding', default=None,
)
coreconfigitem(
    b'convert', b'cvsps.mergefrom', default=None,
)
coreconfigitem(
    b'convert', b'cvsps.mergeto', default=None,
)
coreconfigitem(
    b'convert', b'git.committeractions', default=lambda: [b'messagedifferent'],
)
coreconfigitem(
    b'convert', b'git.extrakeys', default=list,
)
coreconfigitem(
    b'convert', b'git.findcopiesharder', default=False,
)
coreconfigitem(
    b'convert', b'git.remoteprefix', default=b'remote',
)
coreconfigitem(
    b'convert', b'git.renamelimit', default=400,
)
coreconfigitem(
    b'convert', b'git.saverev', default=True,
)
coreconfigitem(
    b'convert', b'git.similarity', default=50,
)
coreconfigitem(
    b'convert', b'git.skipsubmodules', default=False,
)
coreconfigitem(
    b'convert', b'hg.clonebranches', default=False,
)
coreconfigitem(
    b'convert', b'hg.ignoreerrors', default=False,
)
coreconfigitem(
    b'convert', b'hg.preserve-hash', default=False,
)
coreconfigitem(
    b'convert', b'hg.revs', default=None,
)
coreconfigitem(
    b'convert', b'hg.saverev', default=False,
)
coreconfigitem(
    b'convert', b'hg.sourcename', default=None,
)
coreconfigitem(
    b'convert', b'hg.startrev', default=None,
)
coreconfigitem(
    b'convert', b'hg.tagsbranch', default=b'default',
)
coreconfigitem(
    b'convert', b'hg.usebranchnames', default=True,
)
coreconfigitem(
    b'convert', b'ignoreancestorcheck', default=False, experimental=True,
)
coreconfigitem(
    b'convert', b'localtimezone', default=False,
)
coreconfigitem(
    b'convert', b'p4.encoding', default=dynamicdefault,
)
coreconfigitem(
    b'convert', b'p4.startrev', default=0,
)
coreconfigitem(
    b'convert', b'skiptags', default=False,
)
coreconfigitem(
    b'convert', b'svn.debugsvnlog', default=True,
)
coreconfigitem(
    b'convert', b'svn.trunk', default=None,
)
coreconfigitem(
    b'convert', b'svn.tags', default=None,
)
coreconfigitem(
    b'convert', b'svn.branches', default=None,
)
coreconfigitem(
    b'convert', b'svn.startrev', default=0,
)
coreconfigitem(
    b'debug', b'dirstate.delaywrite', default=0,
)
coreconfigitem(
    b'defaults', b'.*', default=None, generic=True,
)
coreconfigitem(
    b'devel', b'all-warnings', default=False,
)
coreconfigitem(
    b'devel', b'bundle2.debug', default=False,
)
coreconfigitem(
    b'devel', b'bundle.delta', default=b'',
)
coreconfigitem(
    b'devel', b'cache-vfs', default=None,
)
coreconfigitem(
    b'devel', b'check-locks', default=False,
)
coreconfigitem(
    b'devel', b'check-relroot', default=False,
)
coreconfigitem(
    b'devel', b'default-date', default=None,
)
coreconfigitem(
    b'devel', b'deprec-warn', default=False,
)
coreconfigitem(
    b'devel', b'disableloaddefaultcerts', default=False,
)
coreconfigitem(
    b'devel', b'warn-empty-changegroup', default=False,
)
coreconfigitem(
    b'devel', b'legacy.exchange', default=list,
)
coreconfigitem(
    b'devel', b'persistent-nodemap', default=False,
)
coreconfigitem(
    b'devel', b'servercafile', default=b'',
)
coreconfigitem(
    b'devel', b'serverexactprotocol', default=b'',
)
coreconfigitem(
    b'devel', b'serverrequirecert', default=False,
)
coreconfigitem(
    b'devel', b'strip-obsmarkers', default=True,
)
coreconfigitem(
    b'devel', b'warn-config', default=None,
)
coreconfigitem(
    b'devel', b'warn-config-default', default=None,
)
coreconfigitem(
    b'devel', b'user.obsmarker', default=None,
)
coreconfigitem(
    b'devel', b'warn-config-unknown', default=None,
)
coreconfigitem(
    b'devel', b'debug.copies', default=False,
)
coreconfigitem(
    b'devel', b'debug.extensions', default=False,
)
coreconfigitem(
    b'devel', b'debug.repo-filters', default=False,
)
coreconfigitem(
    b'devel', b'debug.peer-request', default=False,
)
coreconfigitem(
    b'devel', b'discovery.randomize', default=True,
)
_registerdiffopts(section=b'diff')
coreconfigitem(
    b'email', b'bcc', default=None,
)
coreconfigitem(
    b'email', b'cc', default=None,
)
coreconfigitem(
    b'email', b'charsets', default=list,
)
coreconfigitem(
    b'email', b'from', default=None,
)
coreconfigitem(
    b'email', b'method', default=b'smtp',
)
coreconfigitem(
    b'email', b'reply-to', default=None,
)
coreconfigitem(
    b'email', b'to', default=None,
)
coreconfigitem(
    b'experimental', b'archivemetatemplate', default=dynamicdefault,
)
coreconfigitem(
    b'experimental', b'auto-publish', default=b'publish',
)
coreconfigitem(
    b'experimental', b'bundle-phases', default=False,
)
coreconfigitem(
    b'experimental', b'bundle2-advertise', default=True,
)
coreconfigitem(
    b'experimental', b'bundle2-output-capture', default=False,
)
coreconfigitem(
    b'experimental', b'bundle2.pushback', default=False,
)
coreconfigitem(
    b'experimental', b'bundle2lazylocking', default=False,
)
coreconfigitem(
    b'experimental', b'bundlecomplevel', default=None,
)
coreconfigitem(
    b'experimental', b'bundlecomplevel.bzip2', default=None,
)
coreconfigitem(
    b'experimental', b'bundlecomplevel.gzip', default=None,
)
coreconfigitem(
    b'experimental', b'bundlecomplevel.none', default=None,
)
coreconfigitem(
    b'experimental', b'bundlecomplevel.zstd', default=None,
)
coreconfigitem(
    b'experimental', b'changegroup3', default=False,
)
coreconfigitem(
    b'experimental', b'cleanup-as-archived', default=False,
)
coreconfigitem(
    b'experimental', b'clientcompressionengines', default=list,
)
coreconfigitem(
    b'experimental', b'copytrace', default=b'on',
)
coreconfigitem(
    b'experimental', b'copytrace.movecandidateslimit', default=100,
)
coreconfigitem(
    b'experimental', b'copytrace.sourcecommitlimit', default=100,
)
coreconfigitem(
    b'experimental', b'copies.read-from', default=b"filelog-only",
)
coreconfigitem(
    b'experimental', b'copies.write-to', default=b'filelog-only',
)
coreconfigitem(
    b'experimental', b'crecordtest', default=None,
)
coreconfigitem(
    b'experimental', b'directaccess', default=False,
)
coreconfigitem(
    b'experimental', b'directaccess.revnums', default=False,
)
coreconfigitem(
    b'experimental', b'editortmpinhg', default=False,
)
coreconfigitem(
    b'experimental', b'evolution', default=list,
)
coreconfigitem(
    b'experimental',
    b'evolution.allowdivergence',
    default=False,
    alias=[(b'experimental', b'allowdivergence')],
)
coreconfigitem(
    b'experimental', b'evolution.allowunstable', default=None,
)
coreconfigitem(
    b'experimental', b'evolution.createmarkers', default=None,
)
coreconfigitem(
    b'experimental',
    b'evolution.effect-flags',
    default=True,
    alias=[(b'experimental', b'effect-flags')],
)
coreconfigitem(
    b'experimental', b'evolution.exchange', default=None,
)
coreconfigitem(
    b'experimental', b'evolution.bundle-obsmarker', default=False,
)
coreconfigitem(
    b'experimental', b'log.topo', default=False,
)
coreconfigitem(
    b'experimental', b'evolution.report-instabilities', default=True,
)
coreconfigitem(
    b'experimental', b'evolution.track-operation', default=True,
)
# repo-level config to exclude a revset visibility
#
# The target use case is to use `share` to expose different subset of the same
# repository, especially server side. See also `server.view`.
coreconfigitem(
    b'experimental', b'extra-filter-revs', default=None,
)
coreconfigitem(
    b'experimental', b'maxdeltachainspan', default=-1,
)
coreconfigitem(
    b'experimental', b'mergetempdirprefix', default=None,
)
coreconfigitem(
    b'experimental', b'mmapindexthreshold', default=None,
)
coreconfigitem(
    b'experimental', b'narrow', default=False,
)
coreconfigitem(
    b'experimental', b'nonnormalparanoidcheck', default=False,
)
coreconfigitem(
    b'experimental', b'exportableenviron', default=list,
)
coreconfigitem(
    b'experimental', b'extendedheader.index', default=None,
)
coreconfigitem(
    b'experimental', b'extendedheader.similarity', default=False,
)
coreconfigitem(
    b'experimental', b'graphshorten', default=False,
)
coreconfigitem(
    b'experimental', b'graphstyle.parent', default=dynamicdefault,
)
coreconfigitem(
    b'experimental', b'graphstyle.missing', default=dynamicdefault,
)
coreconfigitem(
    b'experimental', b'graphstyle.grandparent', default=dynamicdefault,
)
coreconfigitem(
    b'experimental', b'hook-track-tags', default=False,
)
coreconfigitem(
    b'experimental', b'httppeer.advertise-v2', default=False,
)
coreconfigitem(
    b'experimental', b'httppeer.v2-encoder-order', default=None,
)
coreconfigitem(
    b'experimental', b'httppostargs', default=False,
)
coreconfigitem(
    b'experimental', b'mergedriver', default=None,
)
coreconfigitem(b'experimental', b'nointerrupt', default=False)
coreconfigitem(b'experimental', b'nointerrupt-interactiveonly', default=True)

coreconfigitem(
    b'experimental', b'obsmarkers-exchange-debug', default=False,
)
coreconfigitem(
    b'experimental', b'remotenames', default=False,
)
coreconfigitem(
    b'experimental', b'removeemptydirs', default=True,
)
coreconfigitem(
    b'experimental', b'revert.interactive.select-to-keep', default=False,
)
coreconfigitem(
    b'experimental', b'revisions.prefixhexnode', default=False,
)
coreconfigitem(
    b'experimental', b'revlogv2', default=None,
)
coreconfigitem(
    b'experimental', b'revisions.disambiguatewithin', default=None,
)
coreconfigitem(
    b'experimental', b'rust.index', default=False,
)
coreconfigitem(
    b'experimental', b'server.filesdata.recommended-batch-size', default=50000,
)
coreconfigitem(
    b'experimental',
    b'server.manifestdata.recommended-batch-size',
    default=100000,
)
coreconfigitem(
    b'experimental', b'server.stream-narrow-clones', default=False,
)
coreconfigitem(
    b'experimental', b'single-head-per-branch', default=False,
)
coreconfigitem(
    b'experimental',
    b'single-head-per-branch:account-closed-heads',
    default=False,
)
coreconfigitem(
    b'experimental', b'sshserver.support-v2', default=False,
)
coreconfigitem(
    b'experimental', b'sparse-read', default=False,
)
coreconfigitem(
    b'experimental', b'sparse-read.density-threshold', default=0.50,
)
coreconfigitem(
    b'experimental', b'sparse-read.min-gap-size', default=b'65K',
)
coreconfigitem(
    b'experimental', b'treemanifest', default=False,
)
coreconfigitem(
    b'experimental', b'update.atomic-file', default=False,
)
coreconfigitem(
    b'experimental', b'sshpeer.advertise-v2', default=False,
)
coreconfigitem(
    b'experimental', b'web.apiserver', default=False,
)
coreconfigitem(
    b'experimental', b'web.api.http-v2', default=False,
)
coreconfigitem(
    b'experimental', b'web.api.debugreflect', default=False,
)
coreconfigitem(
    b'experimental', b'worker.wdir-get-thread-safe', default=False,
)
coreconfigitem(
    b'experimental', b'worker.repository-upgrade', default=False,
)
coreconfigitem(
    b'experimental', b'xdiff', default=False,
)
coreconfigitem(
    b'extensions', b'.*', default=None, generic=True,
)
coreconfigitem(
    b'extdata', b'.*', default=None, generic=True,
)
coreconfigitem(
    b'format', b'bookmarks-in-store', default=False,
)
coreconfigitem(
    b'format', b'chunkcachesize', default=None, experimental=True,
)
coreconfigitem(
    b'format', b'dotencode', default=True,
)
coreconfigitem(
    b'format', b'generaldelta', default=False, experimental=True,
)
coreconfigitem(
    b'format', b'manifestcachesize', default=None, experimental=True,
)
coreconfigitem(
    b'format', b'maxchainlen', default=dynamicdefault, experimental=True,
)
coreconfigitem(
    b'format', b'obsstore-version', default=None,
)
coreconfigitem(
    b'format', b'sparse-revlog', default=True,
)
coreconfigitem(
    b'format',
    b'revlog-compression',
    default=lambda: [b'zlib'],
    alias=[(b'experimental', b'format.compression')],
)
coreconfigitem(
    b'format', b'usefncache', default=True,
)
coreconfigitem(
    b'format', b'usegeneraldelta', default=True,
)
coreconfigitem(
    b'format', b'usestore', default=True,
)
# Right now, the only efficient implement of the nodemap logic is in Rust, so
# the persistent nodemap feature needs to stay experimental as long as the Rust
# extensions are an experimental feature.
coreconfigitem(
    b'format', b'use-persistent-nodemap', default=False, experimental=True
)
coreconfigitem(
    b'format',
    b'exp-use-copies-side-data-changeset',
    default=False,
    experimental=True,
)
coreconfigitem(
    b'format', b'exp-use-side-data', default=False, experimental=True,
)
coreconfigitem(
    b'format', b'internal-phase', default=False, experimental=True,
)
coreconfigitem(
    b'fsmonitor', b'warn_when_unused', default=True,
)
coreconfigitem(
    b'fsmonitor', b'warn_update_file_count', default=50000,
)
coreconfigitem(
    b'help', br'hidden-command\..*', default=False, generic=True,
)
coreconfigitem(
    b'help', br'hidden-topic\..*', default=False, generic=True,
)
coreconfigitem(
    b'hooks', b'.*', default=dynamicdefault, generic=True,
)
coreconfigitem(
    b'hgweb-paths', b'.*', default=list, generic=True,
)
coreconfigitem(
    b'hostfingerprints', b'.*', default=list, generic=True,
)
coreconfigitem(
    b'hostsecurity', b'ciphers', default=None,
)
coreconfigitem(
    b'hostsecurity', b'minimumprotocol', default=dynamicdefault,
)
coreconfigitem(
    b'hostsecurity',
    b'.*:minimumprotocol$',
    default=dynamicdefault,
    generic=True,
)
coreconfigitem(
    b'hostsecurity', b'.*:ciphers$', default=dynamicdefault, generic=True,
)
coreconfigitem(
    b'hostsecurity', b'.*:fingerprints$', default=list, generic=True,
)
coreconfigitem(
    b'hostsecurity', b'.*:verifycertsfile$', default=None, generic=True,
)

coreconfigitem(
    b'http_proxy', b'always', default=False,
)
coreconfigitem(
    b'http_proxy', b'host', default=None,
)
coreconfigitem(
    b'http_proxy', b'no', default=list,
)
coreconfigitem(
    b'http_proxy', b'passwd', default=None,
)
coreconfigitem(
    b'http_proxy', b'user', default=None,
)

coreconfigitem(
    b'http', b'timeout', default=None,
)

coreconfigitem(
    b'logtoprocess', b'commandexception', default=None,
)
coreconfigitem(
    b'logtoprocess', b'commandfinish', default=None,
)
coreconfigitem(
    b'logtoprocess', b'command', default=None,
)
coreconfigitem(
    b'logtoprocess', b'develwarn', default=None,
)
coreconfigitem(
    b'logtoprocess', b'uiblocked', default=None,
)
coreconfigitem(
    b'merge', b'checkunknown', default=b'abort',
)
coreconfigitem(
    b'merge', b'checkignored', default=b'abort',
)
coreconfigitem(
    b'experimental', b'merge.checkpathconflicts', default=False,
)
coreconfigitem(
    b'merge', b'followcopies', default=True,
)
coreconfigitem(
    b'merge', b'on-failure', default=b'continue',
)
coreconfigitem(
    b'merge', b'preferancestor', default=lambda: [b'*'], experimental=True,
)
coreconfigitem(
    b'merge', b'strict-capability-check', default=False,
)
coreconfigitem(
    b'merge-tools', b'.*', default=None, generic=True,
)
coreconfigitem(
    b'merge-tools',
    br'.*\.args$',
    default=b"$local $base $other",
    generic=True,
    priority=-1,
)
coreconfigitem(
    b'merge-tools', br'.*\.binary$', default=False, generic=True, priority=-1,
)
coreconfigitem(
    b'merge-tools', br'.*\.check$', default=list, generic=True, priority=-1,
)
coreconfigitem(
    b'merge-tools',
    br'.*\.checkchanged$',
    default=False,
    generic=True,
    priority=-1,
)
coreconfigitem(
    b'merge-tools',
    br'.*\.executable$',
    default=dynamicdefault,
    generic=True,
    priority=-1,
)
coreconfigitem(
    b'merge-tools', br'.*\.fixeol$', default=False, generic=True, priority=-1,
)
coreconfigitem(
    b'merge-tools', br'.*\.gui$', default=False, generic=True, priority=-1,
)
coreconfigitem(
    b'merge-tools',
    br'.*\.mergemarkers$',
    default=b'basic',
    generic=True,
    priority=-1,
)
coreconfigitem(
    b'merge-tools',
    br'.*\.mergemarkertemplate$',
    default=dynamicdefault,  # take from ui.mergemarkertemplate
    generic=True,
    priority=-1,
)
coreconfigitem(
    b'merge-tools', br'.*\.priority$', default=0, generic=True, priority=-1,
)
coreconfigitem(
    b'merge-tools',
    br'.*\.premerge$',
    default=dynamicdefault,
    generic=True,
    priority=-1,
)
coreconfigitem(
    b'merge-tools', br'.*\.symlink$', default=False, generic=True, priority=-1,
)
coreconfigitem(
    b'pager', b'attend-.*', default=dynamicdefault, generic=True,
)
coreconfigitem(
    b'pager', b'ignore', default=list,
)
coreconfigitem(
    b'pager', b'pager', default=dynamicdefault,
)
coreconfigitem(
    b'patch', b'eol', default=b'strict',
)
coreconfigitem(
    b'patch', b'fuzz', default=2,
)
coreconfigitem(
    b'paths', b'default', default=None,
)
coreconfigitem(
    b'paths', b'default-push', default=None,
)
coreconfigitem(
    b'paths', b'.*', default=None, generic=True,
)
coreconfigitem(
    b'phases', b'checksubrepos', default=b'follow',
)
coreconfigitem(
    b'phases', b'new-commit', default=b'draft',
)
coreconfigitem(
    b'phases', b'publish', default=True,
)
coreconfigitem(
    b'profiling', b'enabled', default=False,
)
coreconfigitem(
    b'profiling', b'format', default=b'text',
)
coreconfigitem(
    b'profiling', b'freq', default=1000,
)
coreconfigitem(
    b'profiling', b'limit', default=30,
)
coreconfigitem(
    b'profiling', b'nested', default=0,
)
coreconfigitem(
    b'profiling', b'output', default=None,
)
coreconfigitem(
    b'profiling', b'showmax', default=0.999,
)
coreconfigitem(
    b'profiling', b'showmin', default=dynamicdefault,
)
coreconfigitem(
    b'profiling', b'showtime', default=True,
)
coreconfigitem(
    b'profiling', b'sort', default=b'inlinetime',
)
coreconfigitem(
    b'profiling', b'statformat', default=b'hotpath',
)
coreconfigitem(
    b'profiling', b'time-track', default=dynamicdefault,
)
coreconfigitem(
    b'profiling', b'type', default=b'stat',
)
coreconfigitem(
    b'progress', b'assume-tty', default=False,
)
coreconfigitem(
    b'progress', b'changedelay', default=1,
)
coreconfigitem(
    b'progress', b'clear-complete', default=True,
)
coreconfigitem(
    b'progress', b'debug', default=False,
)
coreconfigitem(
    b'progress', b'delay', default=3,
)
coreconfigitem(
    b'progress', b'disable', default=False,
)
coreconfigitem(
    b'progress', b'estimateinterval', default=60.0,
)
coreconfigitem(
    b'progress',
    b'format',
    default=lambda: [b'topic', b'bar', b'number', b'estimate'],
)
coreconfigitem(
    b'progress', b'refresh', default=0.1,
)
coreconfigitem(
    b'progress', b'width', default=dynamicdefault,
)
coreconfigitem(
    b'pull', b'confirm', default=False,
)
coreconfigitem(
    b'push', b'pushvars.server', default=False,
)
coreconfigitem(
    b'rewrite',
    b'backup-bundle',
    default=True,
    alias=[(b'ui', b'history-editing-backup')],
)
coreconfigitem(
    b'rewrite', b'update-timestamp', default=False,
)
coreconfigitem(
    b'storage', b'new-repo-backend', default=b'revlogv1', experimental=True,
)
coreconfigitem(
    b'storage',
    b'revlog.optimize-delta-parent-choice',
    default=True,
    alias=[(b'format', b'aggressivemergedeltas')],
)
# experimental as long as rust is experimental (or a C version is implemented)
coreconfigitem(
    b'storage', b'revlog.nodemap.mmap', default=True, experimental=True
)
# experimental as long as format.use-persistent-nodemap is.
coreconfigitem(
    b'storage', b'revlog.nodemap.mode', default=b'compat', experimental=True
)
coreconfigitem(
    b'storage', b'revlog.reuse-external-delta', default=True,
)
coreconfigitem(
    b'storage', b'revlog.reuse-external-delta-parent', default=None,
)
coreconfigitem(
    b'storage', b'revlog.zlib.level', default=None,
)
coreconfigitem(
    b'storage', b'revlog.zstd.level', default=None,
)
coreconfigitem(
    b'server', b'bookmarks-pushkey-compat', default=True,
)
coreconfigitem(
    b'server', b'bundle1', default=True,
)
coreconfigitem(
    b'server', b'bundle1gd', default=None,
)
coreconfigitem(
    b'server', b'bundle1.pull', default=None,
)
coreconfigitem(
    b'server', b'bundle1gd.pull', default=None,
)
coreconfigitem(
    b'server', b'bundle1.push', default=None,
)
coreconfigitem(
    b'server', b'bundle1gd.push', default=None,
)
coreconfigitem(
    b'server',
    b'bundle2.stream',
    default=True,
    alias=[(b'experimental', b'bundle2.stream')],
)
coreconfigitem(
    b'server', b'compressionengines', default=list,
)
coreconfigitem(
    b'server', b'concurrent-push-mode', default=b'check-related',
)
coreconfigitem(
    b'server', b'disablefullbundle', default=False,
)
coreconfigitem(
    b'server', b'maxhttpheaderlen', default=1024,
)
coreconfigitem(
    b'server', b'pullbundle', default=False,
)
coreconfigitem(
    b'server', b'preferuncompressed', default=False,
)
coreconfigitem(
    b'server', b'streamunbundle', default=False,
)
coreconfigitem(
    b'server', b'uncompressed', default=True,
)
coreconfigitem(
    b'server', b'uncompressedallowsecret', default=False,
)
coreconfigitem(
    b'server', b'view', default=b'served',
)
coreconfigitem(
    b'server', b'validate', default=False,
)
coreconfigitem(
    b'server', b'zliblevel', default=-1,
)
coreconfigitem(
    b'server', b'zstdlevel', default=3,
)
coreconfigitem(
    b'share', b'pool', default=None,
)
coreconfigitem(
    b'share', b'poolnaming', default=b'identity',
)
coreconfigitem(
    b'shelve', b'maxbackups', default=10,
)
coreconfigitem(
    b'smtp', b'host', default=None,
)
coreconfigitem(
    b'smtp', b'local_hostname', default=None,
)
coreconfigitem(
    b'smtp', b'password', default=None,
)
coreconfigitem(
    b'smtp', b'port', default=dynamicdefault,
)
coreconfigitem(
    b'smtp', b'tls', default=b'none',
)
coreconfigitem(
    b'smtp', b'username', default=None,
)
coreconfigitem(
    b'sparse', b'missingwarning', default=True, experimental=True,
)
coreconfigitem(
    b'subrepos',
    b'allowed',
    default=dynamicdefault,  # to make backporting simpler
)
coreconfigitem(
    b'subrepos', b'hg:allowed', default=dynamicdefault,
)
coreconfigitem(
    b'subrepos', b'git:allowed', default=dynamicdefault,
)
coreconfigitem(
    b'subrepos', b'svn:allowed', default=dynamicdefault,
)
coreconfigitem(
    b'templates', b'.*', default=None, generic=True,
)
coreconfigitem(
    b'templateconfig', b'.*', default=dynamicdefault, generic=True,
)
coreconfigitem(
    b'trusted', b'groups', default=list,
)
coreconfigitem(
    b'trusted', b'users', default=list,
)
coreconfigitem(
    b'ui', b'_usedassubrepo', default=False,
)
coreconfigitem(
    b'ui', b'allowemptycommit', default=False,
)
coreconfigitem(
    b'ui', b'archivemeta', default=True,
)
coreconfigitem(
    b'ui', b'askusername', default=False,
)
coreconfigitem(
    b'ui', b'clonebundlefallback', default=False,
)
coreconfigitem(
    b'ui', b'clonebundleprefers', default=list,
)
coreconfigitem(
    b'ui', b'clonebundles', default=True,
)
coreconfigitem(
    b'ui', b'color', default=b'auto',
)
coreconfigitem(
    b'ui', b'commitsubrepos', default=False,
)
coreconfigitem(
    b'ui', b'debug', default=False,
)
coreconfigitem(
    b'ui', b'debugger', default=None,
)
coreconfigitem(
    b'ui', b'editor', default=dynamicdefault,
)
coreconfigitem(
    b'ui', b'fallbackencoding', default=None,
)
coreconfigitem(
    b'ui', b'forcecwd', default=None,
)
coreconfigitem(
    b'ui', b'forcemerge', default=None,
)
coreconfigitem(
    b'ui', b'formatdebug', default=False,
)
coreconfigitem(
    b'ui', b'formatjson', default=False,
)
coreconfigitem(
    b'ui', b'formatted', default=None,
)
coreconfigitem(
    b'ui', b'graphnodetemplate', default=None,
)
coreconfigitem(
    b'ui', b'interactive', default=None,
)
coreconfigitem(
    b'ui', b'interface', default=None,
)
coreconfigitem(
    b'ui', b'interface.chunkselector', default=None,
)
coreconfigitem(
    b'ui', b'large-file-limit', default=10000000,
)
coreconfigitem(
    b'ui', b'logblockedtimes', default=False,
)
coreconfigitem(
    b'ui', b'logtemplate', default=None,
)
coreconfigitem(
    b'ui', b'merge', default=None,
)
coreconfigitem(
    b'ui', b'mergemarkers', default=b'basic',
)
coreconfigitem(
    b'ui',
    b'mergemarkertemplate',
    default=(
        b'{node|short} '
        b'{ifeq(tags, "tip", "", '
        b'ifeq(tags, "", "", "{tags} "))}'
        b'{if(bookmarks, "{bookmarks} ")}'
        b'{ifeq(branch, "default", "", "{branch} ")}'
        b'- {author|user}: {desc|firstline}'
    ),
)
coreconfigitem(
    b'ui', b'message-output', default=b'stdio',
)
coreconfigitem(
    b'ui', b'nontty', default=False,
)
coreconfigitem(
    b'ui', b'origbackuppath', default=None,
)
coreconfigitem(
    b'ui', b'paginate', default=True,
)
coreconfigitem(
    b'ui', b'patch', default=None,
)
coreconfigitem(
    b'ui', b'pre-merge-tool-output-template', default=None,
)
coreconfigitem(
    b'ui', b'portablefilenames', default=b'warn',
)
coreconfigitem(
    b'ui', b'promptecho', default=False,
)
coreconfigitem(
    b'ui', b'quiet', default=False,
)
coreconfigitem(
    b'ui', b'quietbookmarkmove', default=False,
)
coreconfigitem(
    b'ui', b'relative-paths', default=b'legacy',
)
coreconfigitem(
    b'ui', b'remotecmd', default=b'hg',
)
coreconfigitem(
    b'ui', b'report_untrusted', default=True,
)
coreconfigitem(
    b'ui', b'rollback', default=True,
)
coreconfigitem(
    b'ui', b'signal-safe-lock', default=True,
)
coreconfigitem(
    b'ui', b'slash', default=False,
)
coreconfigitem(
    b'ui', b'ssh', default=b'ssh',
)
coreconfigitem(
    b'ui', b'ssherrorhint', default=None,
)
coreconfigitem(
    b'ui', b'statuscopies', default=False,
)
coreconfigitem(
    b'ui', b'strict', default=False,
)
coreconfigitem(
    b'ui', b'style', default=b'',
)
coreconfigitem(
    b'ui', b'supportcontact', default=None,
)
coreconfigitem(
    b'ui', b'textwidth', default=78,
)
coreconfigitem(
    b'ui', b'timeout', default=b'600',
)
coreconfigitem(
    b'ui', b'timeout.warn', default=0,
)
coreconfigitem(
    b'ui', b'timestamp-output', default=False,
)
coreconfigitem(
    b'ui', b'traceback', default=False,
)
coreconfigitem(
    b'ui', b'tweakdefaults', default=False,
)
coreconfigitem(b'ui', b'username', alias=[(b'ui', b'user')])
coreconfigitem(
    b'ui', b'verbose', default=False,
)
coreconfigitem(
    b'verify', b'skipflags', default=None,
)
coreconfigitem(
    b'web', b'allowbz2', default=False,
)
coreconfigitem(
    b'web', b'allowgz', default=False,
)
coreconfigitem(
    b'web', b'allow-pull', alias=[(b'web', b'allowpull')], default=True,
)
coreconfigitem(
    b'web', b'allow-push', alias=[(b'web', b'allow_push')], default=list,
)
coreconfigitem(
    b'web', b'allowzip', default=False,
)
coreconfigitem(
    b'web', b'archivesubrepos', default=False,
)
coreconfigitem(
    b'web', b'cache', default=True,
)
coreconfigitem(
    b'web', b'comparisoncontext', default=5,
)
coreconfigitem(
    b'web', b'contact', default=None,
)
coreconfigitem(
    b'web', b'deny_push', default=list,
)
coreconfigitem(
    b'web', b'guessmime', default=False,
)
coreconfigitem(
    b'web', b'hidden', default=False,
)
coreconfigitem(
    b'web', b'labels', default=list,
)
coreconfigitem(
    b'web', b'logoimg', default=b'hglogo.png',
)
coreconfigitem(
    b'web', b'logourl', default=b'https://mercurial-scm.org/',
)
coreconfigitem(
    b'web', b'accesslog', default=b'-',
)
coreconfigitem(
    b'web', b'address', default=b'',
)
coreconfigitem(
    b'web', b'allow-archive', alias=[(b'web', b'allow_archive')], default=list,
)
coreconfigitem(
    b'web', b'allow_read', default=list,
)
coreconfigitem(
    b'web', b'baseurl', default=None,
)
coreconfigitem(
    b'web', b'cacerts', default=None,
)
coreconfigitem(
    b'web', b'certificate', default=None,
)
coreconfigitem(
    b'web', b'collapse', default=False,
)
coreconfigitem(
    b'web', b'csp', default=None,
)
coreconfigitem(
    b'web', b'deny_read', default=list,
)
coreconfigitem(
    b'web', b'descend', default=True,
)
coreconfigitem(
    b'web', b'description', default=b"",
)
coreconfigitem(
    b'web', b'encoding', default=lambda: encoding.encoding,
)
coreconfigitem(
    b'web', b'errorlog', default=b'-',
)
coreconfigitem(
    b'web', b'ipv6', default=False,
)
coreconfigitem(
    b'web', b'maxchanges', default=10,
)
coreconfigitem(
    b'web', b'maxfiles', default=10,
)
coreconfigitem(
    b'web', b'maxshortchanges', default=60,
)
coreconfigitem(
    b'web', b'motd', default=b'',
)
coreconfigitem(
    b'web', b'name', default=dynamicdefault,
)
coreconfigitem(
    b'web', b'port', default=8000,
)
coreconfigitem(
    b'web', b'prefix', default=b'',
)
coreconfigitem(
    b'web', b'push_ssl', default=True,
)
coreconfigitem(
    b'web', b'refreshinterval', default=20,
)
coreconfigitem(
    b'web', b'server-header', default=None,
)
coreconfigitem(
    b'web', b'static', default=None,
)
coreconfigitem(
    b'web', b'staticurl', default=None,
)
coreconfigitem(
    b'web', b'stripes', default=1,
)
coreconfigitem(
    b'web', b'style', default=b'paper',
)
coreconfigitem(
    b'web', b'templates', default=None,
)
coreconfigitem(
    b'web', b'view', default=b'served', experimental=True,
)
coreconfigitem(
    b'worker', b'backgroundclose', default=dynamicdefault,
)
# Windows defaults to a limit of 512 open files. A buffer of 128
# should give us enough headway.
coreconfigitem(
    b'worker', b'backgroundclosemaxqueue', default=384,
)
coreconfigitem(
    b'worker', b'backgroundcloseminfilecount', default=2048,
)
coreconfigitem(
    b'worker', b'backgroundclosethreadcount', default=4,
)
coreconfigitem(
    b'worker', b'enabled', default=True,
)
coreconfigitem(
    b'worker', b'numcpus', default=None,
)

# Rebase related configuration moved to core because other extension are doing
# strange things. For example, shelve import the extensions to reuse some bit
# without formally loading it.
coreconfigitem(
    b'commands', b'rebase.requiredest', default=False,
)
coreconfigitem(
    b'experimental', b'rebaseskipobsolete', default=True,
)
coreconfigitem(
    b'rebase', b'singletransaction', default=False,
)
coreconfigitem(
    b'rebase', b'experimental.inmemory', default=False,
)
