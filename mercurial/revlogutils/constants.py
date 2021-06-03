# revlogdeltas.py - constant used for revlog logic.
#
# Copyright 2005-2007 Olivia Mackall <olivia@selenic.com>
# Copyright 2018 Octobus <contact@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.
"""Helper class to compute deltas stored inside revlogs"""

from __future__ import absolute_import

import struct

from ..interfaces import repository

### Internal utily constants

KIND_CHANGELOG = 1001  # over 256 to not be comparable with a bytes
KIND_MANIFESTLOG = 1002
KIND_FILELOG = 1003
KIND_OTHER = 1004

ALL_KINDS = {
    KIND_CHANGELOG,
    KIND_MANIFESTLOG,
    KIND_FILELOG,
    KIND_OTHER,
}

### main revlog header

# We cannot rely on  Struct.format is inconsistent for python <=3.6 versus above
INDEX_HEADER_FMT = b">I"
INDEX_HEADER = struct.Struct(INDEX_HEADER_FMT)

## revlog version
REVLOGV0 = 0
REVLOGV1 = 1
# Dummy value until file format is finalized.
REVLOGV2 = 0xDEAD
# Dummy value until file format is finalized.
CHANGELOGV2 = 0xD34D

##  global revlog header flags
# Shared across v1 and v2.
FLAG_INLINE_DATA = 1 << 16
# Only used by v1, implied by v2.
FLAG_GENERALDELTA = 1 << 17
REVLOG_DEFAULT_FLAGS = FLAG_INLINE_DATA
REVLOG_DEFAULT_FORMAT = REVLOGV1
REVLOG_DEFAULT_VERSION = REVLOG_DEFAULT_FORMAT | REVLOG_DEFAULT_FLAGS
REVLOGV0_FLAGS = 0
REVLOGV1_FLAGS = FLAG_INLINE_DATA | FLAG_GENERALDELTA
REVLOGV2_FLAGS = FLAG_INLINE_DATA
CHANGELOGV2_FLAGS = 0

### individual entry

## index v0:
#  4 bytes: offset
#  4 bytes: compressed length
#  4 bytes: base rev
#  4 bytes: link rev
# 20 bytes: parent 1 nodeid
# 20 bytes: parent 2 nodeid
# 20 bytes: nodeid
INDEX_ENTRY_V0 = struct.Struct(b">4l20s20s20s")

## index v1
#  6 bytes: offset
#  2 bytes: flags
#  4 bytes: compressed length
#  4 bytes: uncompressed length
#  4 bytes: base rev
#  4 bytes: link rev
#  4 bytes: parent 1 rev
#  4 bytes: parent 2 rev
# 32 bytes: nodeid
INDEX_ENTRY_V1 = struct.Struct(b">Qiiiiii20s12x")
assert INDEX_ENTRY_V1.size == 32 * 2

#  6 bytes: offset
#  2 bytes: flags
#  4 bytes: compressed length
#  4 bytes: uncompressed length
#  4 bytes: base rev
#  4 bytes: link rev
#  4 bytes: parent 1 rev
#  4 bytes: parent 2 rev
# 32 bytes: nodeid
#  8 bytes: sidedata offset
#  4 bytes: sidedata compressed length
#  1 bytes: compression mode (2 lower bit are data_compression_mode)
#  19 bytes: Padding to align to 96 bytes (see RevlogV2Plan wiki page)
INDEX_ENTRY_V2 = struct.Struct(b">Qiiiiii20s12xQiB19x")
assert INDEX_ENTRY_V2.size == 32 * 3, INDEX_ENTRY_V2.size

#  6 bytes: offset
#  2 bytes: flags
#  4 bytes: compressed length
#  4 bytes: uncompressed length
#  4 bytes: parent 1 rev
#  4 bytes: parent 2 rev
# 32 bytes: nodeid
#  8 bytes: sidedata offset
#  4 bytes: sidedata compressed length
#  1 bytes: compression mode (2 lower bit are data_compression_mode)
#  27 bytes: Padding to align to 96 bytes (see RevlogV2Plan wiki page)
INDEX_ENTRY_CL_V2 = struct.Struct(b">Qiiii20s12xQiB27x")
assert INDEX_ENTRY_CL_V2.size == 32 * 3, INDEX_ENTRY_V2.size

# revlog index flags

# For historical reasons, revlog's internal flags were exposed via the
# wire protocol and are even exposed in parts of the storage APIs.

# revision has censor metadata, must be verified
REVIDX_ISCENSORED = repository.REVISION_FLAG_CENSORED
# revision hash does not match data (narrowhg)
REVIDX_ELLIPSIS = repository.REVISION_FLAG_ELLIPSIS
# revision data is stored externally
REVIDX_EXTSTORED = repository.REVISION_FLAG_EXTSTORED
# revision changes files in a way that could affect copy tracing.
REVIDX_HASCOPIESINFO = repository.REVISION_FLAG_HASCOPIESINFO
REVIDX_DEFAULT_FLAGS = 0
# stable order in which flags need to be processed and their processors applied
REVIDX_FLAGS_ORDER = [
    REVIDX_ISCENSORED,
    REVIDX_ELLIPSIS,
    REVIDX_EXTSTORED,
    REVIDX_HASCOPIESINFO,
]

# bitmark for flags that could cause rawdata content change
REVIDX_RAWTEXT_CHANGING_FLAGS = REVIDX_ISCENSORED | REVIDX_EXTSTORED

## chunk compression mode constants:
# These constants are used in revlog version >=2 to denote the compression used
# for a chunk.

# Chunk use no compression, the data stored on disk can be directly use as
# chunk value. Without any header information prefixed.
COMP_MODE_PLAIN = 0

# Chunk use the "default compression" for the revlog (usually defined in the
# revlog docket). A header is still used.
#
# XXX: keeping a header is probably not useful and we should probably drop it.
#
# XXX: The value of allow mixed type of compression in the revlog is unclear
#      and we should consider making PLAIN/DEFAULT the only available mode for
#      revlog v2, disallowing INLINE mode.
COMP_MODE_DEFAULT = 1

# Chunk use a compression mode stored "inline" at the start of the chunk
# itself.  This is the mode always used for revlog version "0" and "1"
COMP_MODE_INLINE = 2

SUPPORTED_FLAGS = {
    REVLOGV0: REVLOGV0_FLAGS,
    REVLOGV1: REVLOGV1_FLAGS,
    REVLOGV2: REVLOGV2_FLAGS,
    CHANGELOGV2: CHANGELOGV2_FLAGS,
}

_no = lambda flags: False
_yes = lambda flags: True


def _from_flag(flag):
    return lambda flags: bool(flags & flag)


FEATURES_BY_VERSION = {
    REVLOGV0: {
        b'inline': _no,
        b'generaldelta': _no,
        b'sidedata': False,
        b'docket': False,
    },
    REVLOGV1: {
        b'inline': _from_flag(FLAG_INLINE_DATA),
        b'generaldelta': _from_flag(FLAG_GENERALDELTA),
        b'sidedata': False,
        b'docket': False,
    },
    REVLOGV2: {
        # The point of inline-revlog is to reduce the number of files used in
        # the store. Using a docket defeat this purpose. So we needs other
        # means to reduce the number of files for revlogv2.
        b'inline': _no,
        b'generaldelta': _yes,
        b'sidedata': True,
        b'docket': True,
    },
    CHANGELOGV2: {
        b'inline': _no,
        # General delta is useless for changelog since we don't do any delta
        b'generaldelta': _no,
        b'sidedata': True,
        b'docket': True,
    },
}


SPARSE_REVLOG_MAX_CHAIN_LENGTH = 1000
