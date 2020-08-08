# requirements.py - objects and functions related to repository requirements
#
# Copyright 2005-2007 Matt Mackall <mpm@selenic.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

# When narrowing is finalized and no longer subject to format changes,
# we should move this to just "narrow" or similar.
NARROW_REQUIREMENT = b'narrowhg-experimental'

# Enables sparse working directory usage
SPARSE_REQUIREMENT = b'exp-sparse'

# Enables the internal phase which is used to hide changesets instead
# of stripping them
INTERNAL_PHASE_REQUIREMENT = b'internal-phase'

# Stores manifest in Tree structure
TREEMANIFEST_REQUIREMENT = b'treemanifest'
