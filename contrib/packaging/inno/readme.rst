Requirements
============

Building the Inno installer requires a Windows machine.

The following system dependencies must be installed:

* Python 2.7 (download from https://www.python.org/downloads/)
* Microsoft Visual C++ Compiler for Python 2.7
  (https://www.microsoft.com/en-us/download/details.aspx?id=44266)
* Windows 10 SDK (download from
  https://developer.microsoft.com/en-us/windows/downloads/windows-10-sdk
  or install via a modern version of Visual Studio)
* Inno Setup (http://jrsoftware.org/isdl.php) version 5.4 or newer.
  Be sure to install the optional Inno Setup Preprocessor feature,
  which is required.
* Python 3.5+ (to run the ``build.py`` script)

Building
========

The ``build.py`` script automates the process of producing an
Inno installer. It manages fetching and configuring the
non-system dependencies (such as py2exe, gettext, and various
Python packages).

The script requires an activated ``Visual C++ 2008`` command prompt.
A shortcut to such a prompt was installed with ``Microsoft Visual C++
Compiler for Python 2.7``. From your Start Menu, look for
``Microsoft Visual C++ Compiler Package for Python 2.7`` then launch
either ``Visual C++ 2008 32-bit Command Prompt`` or
``Visual C++ 2008 64-bit Command Prompt``.

From the prompt, change to the Mercurial source directory. e.g.
``cd c:\src\hg``.

Next, invoke ``build.py`` to produce an Inno installer. You will
need to supply the path to the Python interpreter to use.:

   $ python3.exe contrib\packaging\inno\build.py \
       --python c:\python27\python.exe

.. note::

   The script validates that the Visual C++ environment is
   active and that the architecture of the specified Python
   interpreter matches the Visual C++ environment and errors
   if not.

If everything runs as intended, dependencies will be fetched and
configured into the ``build`` sub-directory, Mercurial will be built,
and an installer placed in the ``dist`` sub-directory. The final
line of output should print the name of the generated installer.

Additional options may be configured. Run ``build.py --help`` to
see a list of program flags.

MinGW
=====

It is theoretically possible to generate an installer that uses
MinGW. This isn't well tested and ``build.py`` and may properly
support it. See old versions of this file in version control for
potentially useful hints as to how to achieve this.
