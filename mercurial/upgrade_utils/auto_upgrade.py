# upgrade.py - functions for automatic upgrade of Mercurial repository
#
# Copyright (c) 2022-present, Pierre-Yves David
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.
from ..i18n import _

from .. import (
    error,
    requirements as requirementsmod,
    scmutil,
)

from . import (
    actions,
    engine,
)


class AutoUpgradeOperation(actions.BaseOperation):
    """A limited Upgrade Operation used to run simple auto upgrade task

    (Expand it as needed in the future)
    """

    def __init__(self, req):
        super().__init__(
            new_requirements=req,
            backup_store=False,
        )


def get_share_safe_action(repo):
    """return an automatic-upgrade action for `share-safe` if applicable

    If no action is needed, return None, otherwise return a callback to upgrade
    or downgrade the repository according the configuration and repository
    format.
    """
    ui = repo.ui
    requirements = repo.requirements
    auto_upgrade_share_source = ui.configbool(
        b'format',
        b'use-share-safe.automatic-upgrade-of-mismatching-repositories',
    )

    action = None

    if (
        auto_upgrade_share_source
        and requirementsmod.SHARED_REQUIREMENT not in requirements
    ):
        sf_config = ui.configbool(b'format', b'use-share-safe')
        sf_local = requirementsmod.SHARESAFE_REQUIREMENT in requirements
        if sf_config and not sf_local:
            msg = _(
                b"automatically upgrading repository to the `share-safe`"
                b" feature\n"
            )
            hint = b"(see `hg help config.format.use-share-safe` for details)\n"

            def action():
                if not ui.quiet:
                    ui.write_err(msg)
                    ui.write_err(hint)
                requirements.add(requirementsmod.SHARESAFE_REQUIREMENT)
                scmutil.writereporequirements(repo, requirements)

        elif sf_local and not sf_config:
            msg = _(
                b"automatically downgrading repository from the `share-safe`"
                b" feature\n"
            )
            hint = b"(see `hg help config.format.use-share-safe` for details)\n"

            def action():
                if not ui.quiet:
                    ui.write_err(msg)
                    ui.write_err(hint)
                requirements.discard(requirementsmod.SHARESAFE_REQUIREMENT)
                scmutil.writereporequirements(repo, requirements)

    return action


def get_tracked_hint_action(repo):
    """return an automatic-upgrade action for `tracked-hint` if applicable

    If no action is needed, return None, otherwise return a callback to upgrade
    or downgrade the repository according the configuration and repository
    format.
    """
    ui = repo.ui
    requirements = set(repo.requirements)
    auto_upgrade_tracked_hint = ui.configbool(
        b'format',
        b'use-dirstate-tracked-hint.automatic-upgrade-of-mismatching-repositories',
    )

    action = None

    if auto_upgrade_tracked_hint:
        th_config = ui.configbool(b'format', b'use-dirstate-tracked-hint')
        th_local = requirementsmod.DIRSTATE_TRACKED_HINT_V1 in requirements
        if th_config and not th_local:
            msg = _(
                b"automatically upgrading repository to the `tracked-hint`"
                b" feature\n"
            )
            hint = b"(see `hg help config.format.use-dirstate-tracked-hint` for details)\n"

            def action():
                if not ui.quiet:
                    ui.write_err(msg)
                    ui.write_err(hint)
                requirements.add(requirementsmod.DIRSTATE_TRACKED_HINT_V1)
                op = AutoUpgradeOperation(requirements)
                engine.upgrade_tracked_hint(ui, repo, op, add=True)

        elif th_local and not th_config:
            msg = _(
                b"automatically downgrading repository from the `tracked-hint`"
                b" feature\n"
            )
            hint = b"(see `hg help config.format.use-dirstate-tracked-hint` for details)\n"

            def action():
                if not ui.quiet:
                    ui.write_err(msg)
                    ui.write_err(hint)
                requirements.discard(requirementsmod.DIRSTATE_TRACKED_HINT_V1)
                op = AutoUpgradeOperation(requirements)
                engine.upgrade_tracked_hint(ui, repo, op, add=False)

    return action


AUTO_UPGRADE_ACTIONS = [
    get_share_safe_action,
    get_tracked_hint_action,
]


def may_auto_upgrade(repo, maker_func):
    """potentially perform auto-upgrade and return the final repository to use

    Auto-upgrade are "quick" repository upgrade that might automatically be run
    by "any" repository access. See `hg help config.format` for automatic
    upgrade documentation.

    note: each relevant upgrades are done one after the other for simplicity.
    This avoid having repository is partially inconsistent state while
    upgrading.

    repo: the current repository instance
    maker_func: a factory function that can recreate a repository after an upgrade
    """
    clear = False

    loop = 0

    while not clear:
        loop += 1
        if loop > 100:
            # XXX basic protection against infinite loop, make it better.
            raise error.ProgrammingError("Too many auto upgrade loops")
        clear = True
        for get_action in AUTO_UPGRADE_ACTIONS:
            action = get_action(repo)
            if action is not None:
                clear = False
                with repo.wlock(wait=False), repo.lock(wait=False):
                    action = get_action(repo)
                    if action is not None:
                        action()
                    repo = maker_func()
    return repo
