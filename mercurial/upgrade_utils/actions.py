# upgrade.py - functions for in place upgrade of Mercurial repository
#
# Copyright (c) 2016-present, Gregory Szorc
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

from ..i18n import _
from .. import (
    error,
    localrepo,
    requirements,
    util,
)

from ..utils import compression

# list of requirements that request a clone of all revlog if added/removed
RECLONES_REQUIREMENTS = {
    b'generaldelta',
    requirements.SPARSEREVLOG_REQUIREMENT,
}


def preservedrequirements(repo):
    return set()


DEFICIENCY = b'deficiency'
OPTIMISATION = b'optimization'


class improvement(object):
    """Represents an improvement that can be made as part of an upgrade.

    The following attributes are defined on each instance:

    name
       Machine-readable string uniquely identifying this improvement. It
       will be mapped to an action later in the upgrade process.

    type
       Either ``DEFICIENCY`` or ``OPTIMISATION``. A deficiency is an obvious
       problem. An optimization is an action (sometimes optional) that
       can be taken to further improve the state of the repository.

    description
       Message intended for humans explaining the improvement in more detail,
       including the implications of it. For ``DEFICIENCY`` types, should be
       worded in the present tense. For ``OPTIMISATION`` types, should be
       worded in the future tense.

    upgrademessage
       Message intended for humans explaining what an upgrade addressing this
       issue will do. Should be worded in the future tense.
    """

    def __init__(self, name, type, description, upgrademessage):
        self.name = name
        self.type = type
        self.description = description
        self.upgrademessage = upgrademessage

    def __eq__(self, other):
        if not isinstance(other, improvement):
            # This is what python tell use to do
            return NotImplemented
        return self.name == other.name

    def __ne__(self, other):
        return not (self == other)

    def __hash__(self):
        return hash(self.name)


allformatvariant = []


def registerformatvariant(cls):
    allformatvariant.append(cls)
    return cls


class formatvariant(improvement):
    """an improvement subclass dedicated to repository format"""

    type = DEFICIENCY
    ### The following attributes should be defined for each class:

    # machine-readable string uniquely identifying this improvement. it will be
    # mapped to an action later in the upgrade process.
    name = None

    # message intended for humans explaining the improvement in more detail,
    # including the implications of it ``DEFICIENCY`` types, should be worded
    # in the present tense.
    description = None

    # message intended for humans explaining what an upgrade addressing this
    # issue will do. should be worded in the future tense.
    upgrademessage = None

    # value of current Mercurial default for new repository
    default = None

    def __init__(self):
        raise NotImplementedError()

    @staticmethod
    def fromrepo(repo):
        """current value of the variant in the repository"""
        raise NotImplementedError()

    @staticmethod
    def fromconfig(repo):
        """current value of the variant in the configuration"""
        raise NotImplementedError()


class requirementformatvariant(formatvariant):
    """formatvariant based on a 'requirement' name.

    Many format variant are controlled by a 'requirement'. We define a small
    subclass to factor the code.
    """

    # the requirement that control this format variant
    _requirement = None

    @staticmethod
    def _newreporequirements(ui):
        return localrepo.newreporequirements(
            ui, localrepo.defaultcreateopts(ui)
        )

    @classmethod
    def fromrepo(cls, repo):
        assert cls._requirement is not None
        return cls._requirement in repo.requirements

    @classmethod
    def fromconfig(cls, repo):
        assert cls._requirement is not None
        return cls._requirement in cls._newreporequirements(repo.ui)


@registerformatvariant
class fncache(requirementformatvariant):
    name = b'fncache'

    _requirement = b'fncache'

    default = True

    description = _(
        b'long and reserved filenames may not work correctly; '
        b'repository performance is sub-optimal'
    )

    upgrademessage = _(
        b'repository will be more resilient to storing '
        b'certain paths and performance of certain '
        b'operations should be improved'
    )


@registerformatvariant
class dotencode(requirementformatvariant):
    name = b'dotencode'

    _requirement = b'dotencode'

    default = True

    description = _(
        b'storage of filenames beginning with a period or '
        b'space may not work correctly'
    )

    upgrademessage = _(
        b'repository will be better able to store files '
        b'beginning with a space or period'
    )


@registerformatvariant
class generaldelta(requirementformatvariant):
    name = b'generaldelta'

    _requirement = b'generaldelta'

    default = True

    description = _(
        b'deltas within internal storage are unable to '
        b'choose optimal revisions; repository is larger and '
        b'slower than it could be; interaction with other '
        b'repositories may require extra network and CPU '
        b'resources, making "hg push" and "hg pull" slower'
    )

    upgrademessage = _(
        b'repository storage will be able to create '
        b'optimal deltas; new repository data will be '
        b'smaller and read times should decrease; '
        b'interacting with other repositories using this '
        b'storage model should require less network and '
        b'CPU resources, making "hg push" and "hg pull" '
        b'faster'
    )


@registerformatvariant
class sharesafe(requirementformatvariant):
    name = b'exp-sharesafe'
    _requirement = requirements.SHARESAFE_REQUIREMENT

    default = False

    description = _(
        b'old shared repositories do not share source repository '
        b'requirements and config. This leads to various problems '
        b'when the source repository format is upgraded or some new '
        b'extensions are enabled.'
    )

    upgrademessage = _(
        b'Upgrades a repository to share-safe format so that future '
        b'shares of this repository share its requirements and configs.'
    )


@registerformatvariant
class sparserevlog(requirementformatvariant):
    name = b'sparserevlog'

    _requirement = requirements.SPARSEREVLOG_REQUIREMENT

    default = True

    description = _(
        b'in order to limit disk reading and memory usage on older '
        b'version, the span of a delta chain from its root to its '
        b'end is limited, whatever the relevant data in this span. '
        b'This can severly limit Mercurial ability to build good '
        b'chain of delta resulting is much more storage space being '
        b'taken and limit reusability of on disk delta during '
        b'exchange.'
    )

    upgrademessage = _(
        b'Revlog supports delta chain with more unused data '
        b'between payload. These gaps will be skipped at read '
        b'time. This allows for better delta chains, making a '
        b'better compression and faster exchange with server.'
    )


@registerformatvariant
class sidedata(requirementformatvariant):
    name = b'sidedata'

    _requirement = requirements.SIDEDATA_REQUIREMENT

    default = False

    description = _(
        b'Allows storage of extra data alongside a revision, '
        b'unlocking various caching options.'
    )

    upgrademessage = _(b'Allows storage of extra data alongside a revision.')


@registerformatvariant
class persistentnodemap(requirementformatvariant):
    name = b'persistent-nodemap'

    _requirement = requirements.NODEMAP_REQUIREMENT

    default = False

    description = _(
        b'persist the node -> rev mapping on disk to speedup lookup'
    )

    upgrademessage = _(b'Speedup revision lookup by node id.')


@registerformatvariant
class copiessdc(requirementformatvariant):
    name = b'copies-sdc'

    _requirement = requirements.COPIESSDC_REQUIREMENT

    default = False

    description = _(b'Stores copies information alongside changesets.')

    upgrademessage = _(
        b'Allows to use more efficient algorithm to deal with ' b'copy tracing.'
    )


@registerformatvariant
class removecldeltachain(formatvariant):
    name = b'plain-cl-delta'

    default = True

    description = _(
        b'changelog storage is using deltas instead of '
        b'raw entries; changelog reading and any '
        b'operation relying on changelog data are slower '
        b'than they could be'
    )

    upgrademessage = _(
        b'changelog storage will be reformated to '
        b'store raw entries; changelog reading will be '
        b'faster; changelog size may be reduced'
    )

    @staticmethod
    def fromrepo(repo):
        # Mercurial 4.0 changed changelogs to not use delta chains. Search for
        # changelogs with deltas.
        cl = repo.changelog
        chainbase = cl.chainbase
        return all(rev == chainbase(rev) for rev in cl)

    @staticmethod
    def fromconfig(repo):
        return True


@registerformatvariant
class compressionengine(formatvariant):
    name = b'compression'
    default = b'zlib'

    description = _(
        b'Compresion algorithm used to compress data. '
        b'Some engine are faster than other'
    )

    upgrademessage = _(
        b'revlog content will be recompressed with the new algorithm.'
    )

    @classmethod
    def fromrepo(cls, repo):
        # we allow multiple compression engine requirement to co-exist because
        # strickly speaking, revlog seems to support mixed compression style.
        #
        # The compression used for new entries will be "the last one"
        compression = b'zlib'
        for req in repo.requirements:
            prefix = req.startswith
            if prefix(b'revlog-compression-') or prefix(b'exp-compression-'):
                compression = req.split(b'-', 2)[2]
        return compression

    @classmethod
    def fromconfig(cls, repo):
        compengines = repo.ui.configlist(b'format', b'revlog-compression')
        # return the first valid value as the selection code would do
        for comp in compengines:
            if comp in util.compengines:
                return comp

        # no valide compression found lets display it all for clarity
        return b','.join(compengines)


@registerformatvariant
class compressionlevel(formatvariant):
    name = b'compression-level'
    default = b'default'

    description = _(b'compression level')

    upgrademessage = _(b'revlog content will be recompressed')

    @classmethod
    def fromrepo(cls, repo):
        comp = compressionengine.fromrepo(repo)
        level = None
        if comp == b'zlib':
            level = repo.ui.configint(b'storage', b'revlog.zlib.level')
        elif comp == b'zstd':
            level = repo.ui.configint(b'storage', b'revlog.zstd.level')
        if level is None:
            return b'default'
        return bytes(level)

    @classmethod
    def fromconfig(cls, repo):
        comp = compressionengine.fromconfig(repo)
        level = None
        if comp == b'zlib':
            level = repo.ui.configint(b'storage', b'revlog.zlib.level')
        elif comp == b'zstd':
            level = repo.ui.configint(b'storage', b'revlog.zstd.level')
        if level is None:
            return b'default'
        return bytes(level)


def finddeficiencies(repo):
    """returns a list of deficiencies that the repo suffer from"""
    deficiencies = []

    # We could detect lack of revlogv1 and store here, but they were added
    # in 0.9.2 and we don't support upgrading repos without these
    # requirements, so let's not bother.

    for fv in allformatvariant:
        if not fv.fromrepo(repo):
            deficiencies.append(fv)

    return deficiencies


ALL_OPTIMISATIONS = []


def register_optimization(obj):
    ALL_OPTIMISATIONS.append(obj)
    return obj


register_optimization(
    improvement(
        name=b're-delta-parent',
        type=OPTIMISATION,
        description=_(
            b'deltas within internal storage will be recalculated to '
            b'choose an optimal base revision where this was not '
            b'already done; the size of the repository may shrink and '
            b'various operations may become faster; the first time '
            b'this optimization is performed could slow down upgrade '
            b'execution considerably; subsequent invocations should '
            b'not run noticeably slower'
        ),
        upgrademessage=_(
            b'deltas within internal storage will choose a new '
            b'base revision if needed'
        ),
    )
)

register_optimization(
    improvement(
        name=b're-delta-multibase',
        type=OPTIMISATION,
        description=_(
            b'deltas within internal storage will be recalculated '
            b'against multiple base revision and the smallest '
            b'difference will be used; the size of the repository may '
            b'shrink significantly when there are many merges; this '
            b'optimization will slow down execution in proportion to '
            b'the number of merges in the repository and the amount '
            b'of files in the repository; this slow down should not '
            b'be significant unless there are tens of thousands of '
            b'files and thousands of merges'
        ),
        upgrademessage=_(
            b'deltas within internal storage will choose an '
            b'optimal delta by computing deltas against multiple '
            b'parents; may slow down execution time '
            b'significantly'
        ),
    )
)

register_optimization(
    improvement(
        name=b're-delta-all',
        type=OPTIMISATION,
        description=_(
            b'deltas within internal storage will always be '
            b'recalculated without reusing prior deltas; this will '
            b'likely make execution run several times slower; this '
            b'optimization is typically not needed'
        ),
        upgrademessage=_(
            b'deltas within internal storage will be fully '
            b'recomputed; this will likely drastically slow down '
            b'execution time'
        ),
    )
)

register_optimization(
    improvement(
        name=b're-delta-fulladd',
        type=OPTIMISATION,
        description=_(
            b'every revision will be re-added as if it was new '
            b'content. It will go through the full storage '
            b'mechanism giving extensions a chance to process it '
            b'(eg. lfs). This is similar to "re-delta-all" but even '
            b'slower since more logic is involved.'
        ),
        upgrademessage=_(
            b'each revision will be added as new content to the '
            b'internal storage; this will likely drastically slow '
            b'down execution time, but some extensions might need '
            b'it'
        ),
    )
)


def findoptimizations(repo):
    """Determine optimisation that could be used during upgrade"""
    # These are unconditionally added. There is logic later that figures out
    # which ones to apply.
    return list(ALL_OPTIMISATIONS)


def determineactions(repo, deficiencies, sourcereqs, destreqs):
    """Determine upgrade actions that will be performed.

    Given a list of improvements as returned by ``finddeficiencies`` and
    ``findoptimizations``, determine the list of upgrade actions that
    will be performed.

    The role of this function is to filter improvements if needed, apply
    recommended optimizations from the improvements list that make sense,
    etc.

    Returns a list of action names.
    """
    newactions = []

    for d in deficiencies:
        name = d._requirement

        # If the action is a requirement that doesn't show up in the
        # destination requirements, prune the action.
        if name is not None and name not in destreqs:
            continue

        newactions.append(d)

    # FUTURE consider adding some optimizations here for certain transitions.
    # e.g. adding generaldelta could schedule parent redeltas.

    return newactions


class UpgradeOperation(object):
    """represent the work to be done during an upgrade"""

    def __init__(self, requirements, actions, revlogs_to_process):
        self.requirements = requirements
        self.actions = actions
        self.revlogs_to_process = revlogs_to_process


###  Code checking if a repository can got through the upgrade process at all. #


def requiredsourcerequirements(repo):
    """Obtain requirements required to be present to upgrade a repo.

    An upgrade will not be allowed if the repository doesn't have the
    requirements returned by this function.
    """
    return {
        # Introduced in Mercurial 0.9.2.
        b'revlogv1',
        # Introduced in Mercurial 0.9.2.
        b'store',
    }


def blocksourcerequirements(repo):
    """Obtain requirements that will prevent an upgrade from occurring.

    An upgrade cannot be performed if the source repository contains a
    requirements in the returned set.
    """
    return {
        # The upgrade code does not yet support these experimental features.
        # This is an artificial limitation.
        requirements.TREEMANIFEST_REQUIREMENT,
        # This was a precursor to generaldelta and was never enabled by default.
        # It should (hopefully) not exist in the wild.
        b'parentdelta',
        # Upgrade should operate on the actual store, not the shared link.
        requirements.SHARED_REQUIREMENT,
    }


def check_source_requirements(repo):
    """Ensure that no existing requirements prevent the repository upgrade"""

    required = requiredsourcerequirements(repo)
    missingreqs = required - repo.requirements
    if missingreqs:
        msg = _(b'cannot upgrade repository; requirement missing: %s')
        missingreqs = b', '.join(sorted(missingreqs))
        raise error.Abort(msg % missingreqs)

    blocking = blocksourcerequirements(repo)
    blockingreqs = blocking & repo.requirements
    if blockingreqs:
        m = _(b'cannot upgrade repository; unsupported source requirement: %s')
        blockingreqs = b', '.join(sorted(blockingreqs))
        raise error.Abort(m % blockingreqs)


### Verify the validity of the planned requirement changes ####################


def supportremovedrequirements(repo):
    """Obtain requirements that can be removed during an upgrade.

    If an upgrade were to create a repository that dropped a requirement,
    the dropped requirement must appear in the returned set for the upgrade
    to be allowed.
    """
    supported = {
        requirements.SPARSEREVLOG_REQUIREMENT,
        requirements.SIDEDATA_REQUIREMENT,
        requirements.COPIESSDC_REQUIREMENT,
        requirements.NODEMAP_REQUIREMENT,
        requirements.SHARESAFE_REQUIREMENT,
    }
    for name in compression.compengines:
        engine = compression.compengines[name]
        if engine.available() and engine.revlogheader():
            supported.add(b'exp-compression-%s' % name)
            if engine.name() == b'zstd':
                supported.add(b'revlog-compression-zstd')
    return supported


def supporteddestrequirements(repo):
    """Obtain requirements that upgrade supports in the destination.

    If the result of the upgrade would create requirements not in this set,
    the upgrade is disallowed.

    Extensions should monkeypatch this to add their custom requirements.
    """
    supported = {
        b'dotencode',
        b'fncache',
        b'generaldelta',
        b'revlogv1',
        b'store',
        requirements.SPARSEREVLOG_REQUIREMENT,
        requirements.SIDEDATA_REQUIREMENT,
        requirements.COPIESSDC_REQUIREMENT,
        requirements.NODEMAP_REQUIREMENT,
        requirements.SHARESAFE_REQUIREMENT,
    }
    for name in compression.compengines:
        engine = compression.compengines[name]
        if engine.available() and engine.revlogheader():
            supported.add(b'exp-compression-%s' % name)
            if engine.name() == b'zstd':
                supported.add(b'revlog-compression-zstd')
    return supported


def allowednewrequirements(repo):
    """Obtain requirements that can be added to a repository during upgrade.

    This is used to disallow proposed requirements from being added when
    they weren't present before.

    We use a list of allowed requirement additions instead of a list of known
    bad additions because the whitelist approach is safer and will prevent
    future, unknown requirements from accidentally being added.
    """
    supported = {
        b'dotencode',
        b'fncache',
        b'generaldelta',
        requirements.SPARSEREVLOG_REQUIREMENT,
        requirements.SIDEDATA_REQUIREMENT,
        requirements.COPIESSDC_REQUIREMENT,
        requirements.NODEMAP_REQUIREMENT,
        requirements.SHARESAFE_REQUIREMENT,
    }
    for name in compression.compengines:
        engine = compression.compengines[name]
        if engine.available() and engine.revlogheader():
            supported.add(b'exp-compression-%s' % name)
            if engine.name() == b'zstd':
                supported.add(b'revlog-compression-zstd')
    return supported


def check_requirements_changes(repo, new_reqs):
    old_reqs = repo.requirements

    support_removal = supportremovedrequirements(repo)
    no_remove_reqs = old_reqs - new_reqs - support_removal
    if no_remove_reqs:
        msg = _(b'cannot upgrade repository; requirement would be removed: %s')
        no_remove_reqs = b', '.join(sorted(no_remove_reqs))
        raise error.Abort(msg % no_remove_reqs)

    support_addition = allowednewrequirements(repo)
    no_add_reqs = new_reqs - old_reqs - support_addition
    if no_add_reqs:
        m = _(b'cannot upgrade repository; do not support adding requirement: ')
        no_add_reqs = b', '.join(sorted(no_add_reqs))
        raise error.Abort(m + no_add_reqs)

    supported = supporteddestrequirements(repo)
    unsupported_reqs = new_reqs - supported
    if unsupported_reqs:
        msg = _(
            b'cannot upgrade repository; do not support destination '
            b'requirement: %s'
        )
        unsupported_reqs = b', '.join(sorted(unsupported_reqs))
        raise error.Abort(msg % unsupported_reqs)
