# upgrade.py - functions for in place upgrade of Mercurial repository
#
# Copyright (c) 2016-present, Gregory Szorc
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

from .i18n import _
from . import (
    error,
    hg,
    localrepo,
    pycompat,
)

from .upgrade_utils import (
    actions as upgrade_actions,
    engine as upgrade_engine,
)

allformatvariant = upgrade_actions.allformatvariant

# search without '-' to support older form on newer client.
#
# We don't enforce backward compatibility for debug command so this
# might eventually be dropped. However, having to use two different
# forms in script when comparing result is anoying enough to add
# backward compatibility for a while.
legacy_opts_map = {
    b'redeltaparent': b're-delta-parent',
    b'redeltamultibase': b're-delta-multibase',
    b'redeltaall': b're-delta-all',
    b'redeltafulladd': b're-delta-fulladd',
}


def upgraderepo(
    ui,
    repo,
    run=False,
    optimize=None,
    backup=True,
    manifest=None,
    changelog=None,
    filelogs=None,
):
    """Upgrade a repository in place."""
    if optimize is None:
        optimize = []
    optimize = {legacy_opts_map.get(o, o) for o in optimize}
    repo = repo.unfiltered()

    revlogs = set(upgrade_engine.UPGRADE_ALL_REVLOGS)
    specentries = (
        (upgrade_engine.UPGRADE_CHANGELOG, changelog),
        (upgrade_engine.UPGRADE_MANIFEST, manifest),
        (upgrade_engine.UPGRADE_FILELOGS, filelogs),
    )
    specified = [(y, x) for (y, x) in specentries if x is not None]
    if specified:
        # we have some limitation on revlogs to be recloned
        if any(x for y, x in specified):
            revlogs = set()
            for upgrade, enabled in specified:
                if enabled:
                    revlogs.add(upgrade)
        else:
            # none are enabled
            for upgrade, __ in specified:
                revlogs.discard(upgrade)

    # Ensure the repository can be upgraded.
    missingreqs = (
        upgrade_actions.requiredsourcerequirements(repo) - repo.requirements
    )
    if missingreqs:
        raise error.Abort(
            _(b'cannot upgrade repository; requirement missing: %s')
            % _(b', ').join(sorted(missingreqs))
        )

    blockedreqs = (
        upgrade_actions.blocksourcerequirements(repo) & repo.requirements
    )
    if blockedreqs:
        raise error.Abort(
            _(
                b'cannot upgrade repository; unsupported source '
                b'requirement: %s'
            )
            % _(b', ').join(sorted(blockedreqs))
        )

    # FUTURE there is potentially a need to control the wanted requirements via
    # command arguments or via an extension hook point.
    newreqs = localrepo.newreporequirements(
        repo.ui, localrepo.defaultcreateopts(repo.ui)
    )
    newreqs.update(upgrade_actions.preservedrequirements(repo))

    noremovereqs = (
        repo.requirements
        - newreqs
        - upgrade_actions.supportremovedrequirements(repo)
    )
    if noremovereqs:
        raise error.Abort(
            _(
                b'cannot upgrade repository; requirement would be '
                b'removed: %s'
            )
            % _(b', ').join(sorted(noremovereqs))
        )

    noaddreqs = (
        newreqs
        - repo.requirements
        - upgrade_actions.allowednewrequirements(repo)
    )
    if noaddreqs:
        raise error.Abort(
            _(
                b'cannot upgrade repository; do not support adding '
                b'requirement: %s'
            )
            % _(b', ').join(sorted(noaddreqs))
        )

    unsupportedreqs = newreqs - upgrade_actions.supporteddestrequirements(repo)
    if unsupportedreqs:
        raise error.Abort(
            _(
                b'cannot upgrade repository; do not support '
                b'destination requirement: %s'
            )
            % _(b', ').join(sorted(unsupportedreqs))
        )

    # Find and validate all improvements that can be made.
    alloptimizations = upgrade_actions.findoptimizations(repo)

    # Apply and Validate arguments.
    optimizations = []
    for o in alloptimizations:
        if o.name in optimize:
            optimizations.append(o)
            optimize.discard(o.name)

    if optimize:  # anything left is unknown
        raise error.Abort(
            _(b'unknown optimization action requested: %s')
            % b', '.join(sorted(optimize)),
            hint=_(b'run without arguments to see valid optimizations'),
        )

    deficiencies = upgrade_actions.finddeficiencies(repo)
    actions = upgrade_actions.determineactions(
        repo, deficiencies, repo.requirements, newreqs
    )
    actions.extend(
        o
        for o in sorted(optimizations)
        # determineactions could have added optimisation
        if o not in actions
    )

    removedreqs = repo.requirements - newreqs
    addedreqs = newreqs - repo.requirements

    if revlogs != upgrade_engine.UPGRADE_ALL_REVLOGS:
        incompatible = upgrade_actions.RECLONES_REQUIREMENTS & (
            removedreqs | addedreqs
        )
        if incompatible:
            msg = _(
                b'ignoring revlogs selection flags, format requirements '
                b'change: %s\n'
            )
            ui.warn(msg % b', '.join(sorted(incompatible)))
            revlogs = upgrade_engine.UPGRADE_ALL_REVLOGS

    def write_labeled(l, label):
        first = True
        for r in sorted(l):
            if not first:
                ui.write(b', ')
            ui.write(r, label=label)
            first = False

    def printrequirements():
        ui.write(_(b'requirements\n'))
        ui.write(_(b'   preserved: '))
        write_labeled(
            newreqs & repo.requirements, "upgrade-repo.requirement.preserved"
        )
        ui.write((b'\n'))
        removed = repo.requirements - newreqs
        if repo.requirements - newreqs:
            ui.write(_(b'   removed: '))
            write_labeled(removed, "upgrade-repo.requirement.removed")
            ui.write((b'\n'))
        added = newreqs - repo.requirements
        if added:
            ui.write(_(b'   added: '))
            write_labeled(added, "upgrade-repo.requirement.added")
            ui.write((b'\n'))
        ui.write(b'\n')

    def printoptimisations():
        optimisations = [
            a for a in actions if a.type == upgrade_actions.OPTIMISATION
        ]
        optimisations.sort(key=lambda a: a.name)
        if optimisations:
            ui.write(_(b'optimisations: '))
            write_labeled(
                [a.name for a in optimisations],
                "upgrade-repo.optimisation.performed",
            )
            ui.write(b'\n\n')

    def printupgradeactions():
        for a in actions:
            ui.status(b'%s\n   %s\n\n' % (a.name, a.upgrademessage))

    def print_affected_revlogs():
        if not revlogs:
            ui.write((b'no revlogs to process\n'))
        else:
            ui.write((b'processed revlogs:\n'))
            for r in sorted(revlogs):
                ui.write((b'  - %s\n' % r))
        ui.write((b'\n'))

    if not run:
        fromconfig = []
        onlydefault = []

        for d in deficiencies:
            if d.fromconfig(repo):
                fromconfig.append(d)
            elif d.default:
                onlydefault.append(d)

        if fromconfig or onlydefault:

            if fromconfig:
                ui.status(
                    _(
                        b'repository lacks features recommended by '
                        b'current config options:\n\n'
                    )
                )
                for i in fromconfig:
                    ui.status(b'%s\n   %s\n\n' % (i.name, i.description))

            if onlydefault:
                ui.status(
                    _(
                        b'repository lacks features used by the default '
                        b'config options:\n\n'
                    )
                )
                for i in onlydefault:
                    ui.status(b'%s\n   %s\n\n' % (i.name, i.description))

            ui.status(b'\n')
        else:
            ui.status(
                _(
                    b'(no feature deficiencies found in existing '
                    b'repository)\n'
                )
            )

        ui.status(
            _(
                b'performing an upgrade with "--run" will make the following '
                b'changes:\n\n'
            )
        )

        printrequirements()
        printoptimisations()
        printupgradeactions()
        print_affected_revlogs()

        unusedoptimize = [i for i in alloptimizations if i not in actions]

        if unusedoptimize:
            ui.status(
                _(
                    b'additional optimizations are available by specifying '
                    b'"--optimize <name>":\n\n'
                )
            )
            for i in unusedoptimize:
                ui.status(_(b'%s\n   %s\n\n') % (i.name, i.description))
        return

    # Else we're in the run=true case.
    ui.write(_(b'upgrade will perform the following actions:\n\n'))
    printrequirements()
    printoptimisations()
    printupgradeactions()
    print_affected_revlogs()

    upgradeactions = [a.name for a in actions]

    ui.status(_(b'beginning upgrade...\n'))
    with repo.wlock(), repo.lock():
        ui.status(_(b'repository locked and read-only\n'))
        # Our strategy for upgrading the repository is to create a new,
        # temporary repository, write data to it, then do a swap of the
        # data. There are less heavyweight ways to do this, but it is easier
        # to create a new repo object than to instantiate all the components
        # (like the store) separately.
        tmppath = pycompat.mkdtemp(prefix=b'upgrade.', dir=repo.path)
        backuppath = None
        try:
            ui.status(
                _(
                    b'creating temporary repository to stage migrated '
                    b'data: %s\n'
                )
                % tmppath
            )

            # clone ui without using ui.copy because repo.ui is protected
            repoui = repo.ui.__class__(repo.ui)
            dstrepo = hg.repository(repoui, path=tmppath, create=True)

            with dstrepo.wlock(), dstrepo.lock():
                backuppath = upgrade_engine.upgrade(
                    ui, repo, dstrepo, newreqs, upgradeactions, revlogs=revlogs
                )
            if not (backup or backuppath is None):
                ui.status(
                    _(b'removing old repository content%s\n') % backuppath
                )
                repo.vfs.rmtree(backuppath, forcibly=True)
                backuppath = None

        finally:
            ui.status(_(b'removing temporary repository %s\n') % tmppath)
            repo.vfs.rmtree(tmppath, forcibly=True)

            if backuppath and not ui.quiet:
                ui.warn(
                    _(b'copy of old repository backed up at %s\n') % backuppath
                )
                ui.warn(
                    _(
                        b'the old repository will not be deleted; remove '
                        b'it to free up disk space once the upgraded '
                        b'repository is verified\n'
                    )
                )

            if upgrade_actions.sharesafe.name in addedreqs:
                ui.warn(
                    _(
                        b'repository upgraded to share safe mode, existing'
                        b' shares will still work in old non-safe mode. '
                        b'Re-share existing shares to use them in safe mode'
                        b' New shares will be created in safe mode.\n'
                    )
                )
            if upgrade_actions.sharesafe.name in removedreqs:
                ui.warn(
                    _(
                        b'repository downgraded to not use share safe mode, '
                        b'existing shares will not work and needs to'
                        b' be reshared.\n'
                    )
                )
