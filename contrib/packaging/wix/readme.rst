WiX Installer
=============

The files in this directory are used to produce an MSI installer using
the WiX Toolset (http://wixtoolset.org/).

The MSI installers require elevated (admin) privileges due to the
installation of MSVC CRT libraries into the Windows system store. See
the Inno Setup installers in the ``inno`` sibling directory for installers
that do not have this requirement.

Requirements
============

Building the WiX installers requires a Windows machine. The following
dependencies must be installed:

* Python 2.7 (download from https://www.python.org/downloads/)
* Microsoft Visual C++ Compiler for Python 2.7
  (https://www.microsoft.com/en-us/download/details.aspx?id=44266)
* Python 3.5+ (to run the ``packaging.py`` script)

Building
========

The ``packaging.py`` script automates the process of producing an MSI
installer. It manages fetching and configuring non-system dependencies
(such as py2exe, gettext, and various Python packages).

The script requires an activated ``Visual C++ 2008`` command prompt.
A shortcut to such a prompt was installed with ``Microsoft Visual
C++ Compiler for Python 2.7``. From your Start Menu, look for
``Microsoft Visual C++ Compiler Package for Python 2.7`` then
launch either ``Visual C++ 2008 32-bit Command Prompt`` or
``Visual C++ 2008 64-bit Command Prompt``.

From the prompt, change to the Mercurial source directory. e.g.
``cd c:\src\hg``.

Next, invoke ``packaging.py`` to produce an MSI installer. You will need
to supply the path to the Python interpreter to use.::

   $ python3 contrib\packaging\packaging.py \
      wix --python c:\python27\python.exe

.. note::

   The script validates that the Visual C++ environment is active and
   that the architecture of the specified Python interpreter matches the
   Visual C++ environment. An error is raised otherwise.

If everything runs as intended, dependencies will be fetched and
configured into the ``build`` sub-directory, Mercurial will be built,
and an installer placed in the ``dist`` sub-directory. The final line
of output should print the name of the generated installer.

Additional options may be configured. Run ``packaging.py wix --help`` to
see a list of program flags.

Relationship to TortoiseHG
==========================

TortoiseHG uses the WiX files in this directory.

The code for building TortoiseHG installers lives at
https://bitbucket.org/tortoisehg/thg-winbuild and is maintained by
Steve Borho (steve@borho.org).

When changing behavior of the WiX installer, be sure to notify
the TortoiseHG Project of the changes so they have ample time
provide feedback and react to those changes.
