# resourceutil.py - utility for looking up resources
#
#  Copyright 2005 K. Thananchayan <thananck@yahoo.com>
#  Copyright 2005-2007 Matt Mackall <mpm@selenic.com>
#  Copyright 2006 Vadim Gelfer <vadim.gelfer@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import imp
import os
import sys

from .. import pycompat


def mainfrozen():
    """return True if we are a frozen executable.

    The code supports py2exe (most common, Windows only) and tools/freeze
    (portable, not much used).
    """
    return (
        pycompat.safehasattr(sys, "frozen")
        or pycompat.safehasattr(sys, "importers")  # new py2exe
        or imp.is_frozen("__main__")  # old py2exe
    )  # tools/freeze


# the location of data files matching the source code
if mainfrozen() and getattr(sys, 'frozen', None) != 'macosx_app':
    # executable version (py2exe) doesn't support __file__
    datapath = os.path.dirname(pycompat.sysexecutable)
else:
    datapath = os.path.dirname(os.path.dirname(pycompat.fsencode(__file__)))
