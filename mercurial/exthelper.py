# Copyright 2012 Logilab SA        <contact@logilab.fr>
#                Pierre-Yves David <pierre-yves.david@ens-lyon.org>
#                Octobus <contact@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

#####################################################################
### Extension helper                                              ###
#####################################################################

from __future__ import absolute_import

from . import (
    commands,
    extensions,
    registrar,
)

class exthelper(object):
    """Helper for modular extension setup

    A single helper should be instantiated for each extension. Helper
    methods are then used as decorators for various purpose.

    All decorators return the original function and may be chained.
    """

    def __init__(self):
        self._uipopulatecallables = []
        self._uicallables = []
        self._extcallables = []
        self._repocallables = []
        self._commandwrappers = []
        self._extcommandwrappers = []
        self._functionwrappers = []
        self._duckpunchers = []
        self.cmdtable = {}
        self.command = registrar.command(self.cmdtable)
        self.configtable = {}
        self.configitem = registrar.configitem(self.configtable)

    def merge(self, other):
        self._uicallables.extend(other._uicallables)
        self._uipopulatecallables.extend(other._uipopulatecallables)
        self._extcallables.extend(other._extcallables)
        self._repocallables.extend(other._repocallables)
        self._commandwrappers.extend(other._commandwrappers)
        self._extcommandwrappers.extend(other._extcommandwrappers)
        self._functionwrappers.extend(other._functionwrappers)
        self._duckpunchers.extend(other._duckpunchers)
        self.cmdtable.update(other.cmdtable)
        for section, items in other.configtable.iteritems():
            if section in self.configtable:
                self.configtable[section].update(items)
            else:
                self.configtable[section] = items

    def finaluisetup(self, ui):
        """Method to be used as the extension uisetup

        The following operations belong here:

        - Changes to ui.__class__ . The ui object that will be used to run the
          command has not yet been created. Changes made here will affect ui
          objects created after this, and in particular the ui that will be
          passed to runcommand
        - Command wraps (extensions.wrapcommand)
        - Changes that need to be visible to other extensions: because
          initialization occurs in phases (all extensions run uisetup, then all
          run extsetup), a change made here will be visible to other extensions
          during extsetup
        - Monkeypatch or wrap function (extensions.wrapfunction) of dispatch
          module members
        - Setup of pre-* and post-* hooks
        - pushkey setup
        """
        for cont, funcname, func in self._duckpunchers:
            setattr(cont, funcname, func)
        for command, wrapper, opts in self._commandwrappers:
            entry = extensions.wrapcommand(commands.table, command, wrapper)
            if opts:
                for short, long, val, msg in opts:
                    entry[1].append((short, long, val, msg))
        for cont, funcname, wrapper in self._functionwrappers:
            extensions.wrapfunction(cont, funcname, wrapper)
        for c in self._uicallables:
            c(ui)

    def finaluipopulate(self, ui):
        """Method to be used as the extension uipopulate

        This is called once per ui instance to:

        - Set up additional ui members
        - Update configuration by ``ui.setconfig()``
        - Extend the class dynamically
        """
        for c in self._uipopulatecallables:
            c(ui)

    def finalextsetup(self, ui):
        """Method to be used as a the extension extsetup

        The following operations belong here:

        - Changes depending on the status of other extensions. (if
          extensions.find('mq'))
        - Add a global option to all commands
        """
        knownexts = {}

        for ext, command, wrapper, opts in self._extcommandwrappers:
            if ext not in knownexts:
                try:
                    e = extensions.find(ext)
                except KeyError:
                    # Extension isn't enabled, so don't bother trying to wrap
                    # it.
                    continue
                knownexts[ext] = e.cmdtable
            entry = extensions.wrapcommand(knownexts[ext], command, wrapper)
            if opts:
                for short, long, val, msg in opts:
                    entry[1].append((short, long, val, msg))

        for c in self._extcallables:
            c(ui)

    def finalreposetup(self, ui, repo):
        """Method to be used as the extension reposetup

        The following operations belong here:

        - All hooks but pre-* and post-*
        - Modify configuration variables
        - Changes to repo.__class__, repo.dirstate.__class__
        """
        for c in self._repocallables:
            c(ui, repo)

    def uisetup(self, call):
        """Decorated function will be executed during uisetup

        example::

            @eh.uisetup
            def setupbabar(ui):
                print 'this is uisetup!'
        """
        self._uicallables.append(call)
        return call

    def uipopulate(self, call):
        """Decorated function will be executed during uipopulate

        example::

            @eh.uipopulate
            def setupfoo(ui):
                print 'this is uipopulate!'
        """
        self._uipopulatecallables.append(call)
        return call

    def extsetup(self, call):
        """Decorated function will be executed during extsetup

        example::

            @eh.extsetup
            def setupcelestine(ui):
                print 'this is extsetup!'
        """
        self._extcallables.append(call)
        return call

    def reposetup(self, call):
        """Decorated function will be executed during reposetup

        example::

            @eh.reposetup
            def setupzephir(ui, repo):
                print 'this is reposetup!'
        """
        self._repocallables.append(call)
        return call

    def wrapcommand(self, command, extension=None, opts=None):
        """Decorated function is a command wrapper

        The name of the command must be given as the decorator argument.
        The wrapping is installed during `uisetup`.

        If the second option `extension` argument is provided, the wrapping
        will be applied in the extension commandtable. This argument must be a
        string that will be searched using `extension.find` if not found and
        Abort error is raised. If the wrapping applies to an extension, it is
        installed during `extsetup`.

        example::

            @eh.wrapcommand('summary')
            def wrapsummary(orig, ui, repo, *args, **kwargs):
                ui.note('Barry!')
                return orig(ui, repo, *args, **kwargs)

        The `opts` argument allows specifying additional arguments for the
        command.

        """
        if opts is None:
            opts = []
        def dec(wrapper):
            if extension is None:
                self._commandwrappers.append((command, wrapper, opts))
            else:
                self._extcommandwrappers.append((extension, command, wrapper,
                                                 opts))
            return wrapper
        return dec

    def wrapfunction(self, container, funcname):
        """Decorated function is a function wrapper

        This function takes two arguments, the container and the name of the
        function to wrap. The wrapping is performed during `uisetup`.
        (there is no extension support)

        example::

            @eh.function(discovery, 'checkheads')
            def wrapfunction(orig, *args, **kwargs):
                ui.note('His head smashed in and his heart cut out')
                return orig(*args, **kwargs)
        """
        def dec(wrapper):
            self._functionwrappers.append((container, funcname, wrapper))
            return wrapper
        return dec

    def addattr(self, container, funcname):
        """Decorated function is to be added to the container

        This function takes two arguments, the container and the name of the
        function to wrap. The wrapping is performed during `uisetup`.

        Adding attributes to a container like this is discouraged, because the
        container modification is visible even in repositories that do not
        have the extension loaded.  Therefore, care must be taken that the
        function doesn't make assumptions that the extension was loaded for the
        current repository.  For `ui` and `repo` instances, a better option is
        to subclass the instance in `uipopulate` and `reposetup` respectively.

        https://www.mercurial-scm.org/wiki/WritingExtensions

        example::

            @eh.addattr(context.changectx, 'babar')
            def babar(ctx):
                return 'babar' in ctx.description
        """
        def dec(func):
            self._duckpunchers.append((container, funcname, func))
            return func
        return dec
