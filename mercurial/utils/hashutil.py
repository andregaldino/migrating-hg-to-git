from __future__ import absolute_import

import hashlib

try:
    from ..thirdparty import sha1dc

    sha1 = sha1dc.sha1
except (ImportError, AttributeError):
    sha1 = hashlib.sha1