from __future__ import absolute_import

import base64

from mercurial.hgweb import common

def perform_authentication(hgweb, req, op):
    auth = req.headers.get(b'Authorization')
    if not auth:
        raise common.ErrorResponse(common.HTTP_UNAUTHORIZED, b'who',
                [(b'WWW-Authenticate', b'Basic Realm="mercurial"')])

    if base64.b64decode(auth.split()[1]).split(b':', 1) != [b'user', b'pass']:
        raise common.ErrorResponse(common.HTTP_FORBIDDEN, b'no')

def extsetup(ui):
    common.permhooks.insert(0, perform_authentication)
