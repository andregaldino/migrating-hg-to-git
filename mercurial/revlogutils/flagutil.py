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

def addflagprocessor(flag, processor):
    """Register a flag processor on a revision data flag.

    Invariant:
    - Flags need to be defined in REVIDX_KNOWN_FLAGS and REVIDX_FLAGS_ORDER,
      and REVIDX_RAWTEXT_CHANGING_FLAGS if they can alter rawtext.
    - Only one flag processor can be registered on a specific flag.
    - flagprocessors must be 3-tuples of functions (read, write, raw) with the
      following signatures:
          - (read)  f(self, rawtext) -> text, bool
          - (write) f(self, text) -> rawtext, bool
          - (raw)   f(self, rawtext) -> bool
      "text" is presented to the user. "rawtext" is stored in revlog data, not
      directly visible to the user.
      The boolean returned by these transforms is used to determine whether
      the returned text can be used for hash integrity checking. For example,
      if "write" returns False, then "text" is used to generate hash. If
      "write" returns True, that basically means "rawtext" returned by "write"
      should be used to generate hash. Usually, "write" and "read" return
      different booleans. And "raw" returns a same boolean as "write".

      Note: The 'raw' transform is used for changegroup generation and in some
      debug commands. In this case the transform only indicates whether the
      contents can be used for hash integrity checks.
    """
    insertflagprocessor(flag, processor, flagprocessors)

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