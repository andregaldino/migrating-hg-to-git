# flagutils.py - code to deal with revlog flags and their processors
#
# Copyright 2016 Remi Chaintron <remi@fb.com>
# Copyright 2016-2019 Pierre-Yves David <pierre-yves.david@ens-lyon.org>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

from ..i18n import _

from .constants import (
    REVIDX_DEFAULT_FLAGS,
    REVIDX_ELLIPSIS,
    REVIDX_EXTSTORED,
    REVIDX_FLAGS_ORDER,
    REVIDX_ISCENSORED,
    REVIDX_RAWTEXT_CHANGING_FLAGS,
)

from .. import (
    error,
    util
)

# blanked usage of all the name to prevent pyflakes constraints
# We need these name available in the module for extensions.
REVIDX_ISCENSORED
REVIDX_ELLIPSIS
REVIDX_EXTSTORED
REVIDX_DEFAULT_FLAGS
REVIDX_FLAGS_ORDER
REVIDX_RAWTEXT_CHANGING_FLAGS

REVIDX_KNOWN_FLAGS = util.bitsfrom(REVIDX_FLAGS_ORDER)

# Store flag processors (cf. 'addflagprocessor()' to register)
flagprocessors = {
    REVIDX_ISCENSORED: None,
}

def insertflagprocessor(flag, processor, flagprocessors):
    if not flag & REVIDX_KNOWN_FLAGS:
        msg = _("cannot register processor on unknown flag '%#x'.") % (flag)
        raise error.ProgrammingError(msg)
    if flag not in REVIDX_FLAGS_ORDER:
        msg = _("flag '%#x' undefined in REVIDX_FLAGS_ORDER.") % (flag)
        raise error.ProgrammingError(msg)
    if flag in flagprocessors:
        msg = _("cannot register multiple processors on flag '%#x'.") % (flag)
        raise error.Abort(msg)
    flagprocessors[flag] = processor
