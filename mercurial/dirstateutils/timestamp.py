# Copyright Mercurial Contributors
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import stat


rangemask = 0x7FFFFFFF


class timestamp(tuple):
    """
    A Unix timestamp with nanoseconds precision,
    modulo 2**31 seconds.

    A 2-tuple containing:

    `truncated_seconds`: seconds since the Unix epoch,
    truncated to its lower 31 bits

    `subsecond_nanoseconds`: number of nanoseconds since `truncated_seconds`.
    """

    def __new__(cls, value):
        truncated_seconds, subsec_nanos = value
        value = (truncated_seconds & rangemask, subsec_nanos)
        return super(timestamp, cls).__new__(cls, value)


def zero():
    """
    Returns the `timestamp` at the Unix epoch.
    """
    return tuple.__new__(timestamp, (0, 0))


def mtime_of(stat_result):
    """
    Takes an `os.stat_result`-like object and returns a `timestamp` object
    for its modification time.
    """
    # https://docs.python.org/2/library/os.html#os.stat_float_times
    # "For compatibility with older Python versions,
    #  accessing stat_result as a tuple always returns integers."
    secs = stat_result[stat.ST_MTIME]

    # For now
    subsec_nanos = 0

    return timestamp((secs, subsec_nanos))
