# badserverext.py - Extension making servers behave badly
#
# Copyright 2017 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# no-check-code

"""Extension to make servers behave badly.

This extension is useful for testing Mercurial behavior when various network
events occur.

Various config options in the [badserver] section influence behavior:

close-before-accept
   If true, close() the server socket when a new connection arrives before
   accept() is called. The server will then exit.

close-after-accept
   If true, the server will close() the client socket immediately after
   accept().

close-after-recv-bytes
   If defined, close the client socket after receiving this many bytes.
   (The value is a list, multiple values can use used to close a series of requests
   request)

close-after-recv-patterns
   If defined, the `close-after-recv-bytes` values only start counting after the
   `read` operation that encountered the defined patterns.
   (The value is a list, multiple values can use used to close a series of requests
   request)

close-after-send-bytes
   If defined, close the client socket after sending this many bytes.
   (The value is a list, multiple values can use used to close a series of requests
   request)

close-after-send-patterns
   If defined, close the client socket after the configured regexp is seen.
   (The value is a list, multiple values can use used to close a series of requests
   request)
"""


import re
import socket

from mercurial import (
    registrar,
)

from mercurial.hgweb import server

configtable = {}
configitem = registrar.configitem(configtable)

configitem(
    b'badserver',
    b'close-after-accept',
    default=False,
)
configitem(
    b'badserver',
    b'close-after-recv-bytes',
    default=b'0',
)
configitem(
    b'badserver',
    b'close-after-recv-patterns',
    default=b'',
)
configitem(
    b'badserver',
    b'close-after-send-bytes',
    default=b'0',
)
configitem(
    b'badserver',
    b'close-after-send-patterns',
    default=b'',
)
configitem(
    b'badserver',
    b'close-before-accept',
    default=False,
)


class ConditionTracker:
    def __init__(
        self,
        close_after_recv_bytes,
        close_after_recv_patterns,
        close_after_send_bytes,
        close_after_send_patterns,
    ):
        self._all_close_after_recv_bytes = close_after_recv_bytes
        self._all_close_after_recv_patterns = close_after_recv_patterns
        self._all_close_after_send_bytes = close_after_send_bytes
        self._all_close_after_send_patterns = close_after_send_patterns

        self.target_recv_bytes = None
        self.remaining_recv_bytes = None
        self.recv_patterns = None
        self.recv_data = b''
        self.target_send_bytes = None
        self.remaining_send_bytes = None
        self.send_pattern = None
        self.send_data = b''

    def start_next_request(self):
        """move to the next set of close condition"""
        if self._all_close_after_recv_bytes:
            self.target_recv_bytes = self._all_close_after_recv_bytes.pop(0)
            self.remaining_recv_bytes = self.target_recv_bytes
        else:
            self.target_recv_bytes = None
            self.remaining_recv_bytes = None

        self.recv_data = b''
        if self._all_close_after_recv_patterns:
            self.recv_pattern = self._all_close_after_recv_patterns.pop(0)
        else:
            self.recv_pattern = None

        if self._all_close_after_send_bytes:
            self.target_send_bytes = self._all_close_after_send_bytes.pop(0)
            self.remaining_send_bytes = self.target_send_bytes
        else:
            self.target_send_bytes = None
            self.remaining_send_bytes = None

        self.send_data = b''
        if self._all_close_after_send_patterns:
            self.send_pattern = self._all_close_after_send_patterns.pop(0)
        else:
            self.send_pattern = None

    def might_close(self):
        """True, if any processing will be needed"""
        if self.remaining_recv_bytes is not None:
            return True
        if self.recv_pattern is not None:
            return True
        if self.remaining_send_bytes is not None:
            return True
        if self.send_pattern is not None:
            return True
        return False

    def forward_write(self, obj, method, data, *args, **kwargs):
        """call an underlying write function until condition are met

        When the condition are met the socket is closed
        """
        remaining = self.remaining_send_bytes
        pattern = self.send_pattern

        orig = object.__getattribute__(obj, '_orig')
        bmethod = method.encode('ascii')
        func = getattr(orig, method)

        if pattern:
            self.send_data += data
            pieces = pattern.split(self.send_data, maxsplit=1)
            if len(pieces) > 1:
                dropped = len(pieces[-1])
                remaining = len(data) - dropped

        if remaining:
            remaining = max(0, remaining)

        if not remaining:
            newdata = data
        else:
            if remaining < len(data):
                newdata = data[0:remaining]
            else:
                newdata = data
            remaining -= len(newdata)
            self.remaining_send_bytes = remaining

        result = func(newdata, *args, **kwargs)

        if remaining is None:
            obj._writelog(b'%s(%d) -> %s' % (bmethod, len(data), data))
        else:
            msg = b'%s(%d from %d) -> (%d) %s'
            msg %= (bmethod, len(newdata), len(data), remaining, newdata)
            obj._writelog(msg)

        if remaining is not None and remaining <= 0:
            obj._writelog(b'write limit reached; closing socket')
            object.__getattribute__(obj, '_cond_close')()
            raise Exception('connection closed after sending N bytes')

        return result

    def forward_read(self, obj, method, size=-1):
        """call an underlying read function until condition are met

        When the condition are met the socket is closed
        """
        remaining = self.remaining_recv_bytes
        pattern = self.recv_pattern

        orig = object.__getattribute__(obj, '_orig')
        bmethod = method.encode('ascii')
        func = getattr(orig, method)

        requested_size = size
        actual_size = size

        if pattern is None and remaining:
            if size < 0:
                actual_size = remaining
            else:
                actual_size = min(remaining, requested_size)

        result = func(actual_size)

        if pattern is None and remaining:
            remaining -= len(result)
            self.remaining_recv_bytes = remaining

        if requested_size == 65537:
            requested_repr = b'~'
        else:
            requested_repr = b'%d' % requested_size
        if requested_size == actual_size:
            msg = b'%s(%s) -> (%d) %s'
            msg %= (bmethod, requested_repr, len(result), result)
        else:
            msg = b'%s(%d from %s) -> (%d) %s'
            msg %= (bmethod, actual_size, requested_repr, len(result), result)
        obj._writelog(msg)

        if pattern is not None:
            self.recv_data += result
            if pattern.search(self.recv_data):
                # start counting bytes starting with the next read
                self.recv_pattern = None

        if remaining is not None and remaining <= 0:
            obj._writelog(b'read limit reached; closing socket')
            obj._cond_close()

            # This is the easiest way to abort the current request.
            raise Exception('connection closed after receiving N bytes')

        return result


# We can't adjust __class__ on a socket instance. So we define a proxy type.
class socketproxy:
    __slots__ = ('_orig', '_logfp', '_cond')

    def __init__(self, obj, logfp, condition_tracked):
        object.__setattr__(self, '_orig', obj)
        object.__setattr__(self, '_logfp', logfp)
        object.__setattr__(self, '_cond', condition_tracked)

    def __getattribute__(self, name):
        if name in ('makefile', 'sendall', '_writelog', '_cond_close'):
            return object.__getattribute__(self, name)

        return getattr(object.__getattribute__(self, '_orig'), name)

    def __delattr__(self, name):
        delattr(object.__getattribute__(self, '_orig'), name)

    def __setattr__(self, name, value):
        setattr(object.__getattribute__(self, '_orig'), name, value)

    def _writelog(self, msg):
        msg = msg.replace(b'\r', b'\\r').replace(b'\n', b'\\n')

        object.__getattribute__(self, '_logfp').write(msg)
        object.__getattribute__(self, '_logfp').write(b'\n')
        object.__getattribute__(self, '_logfp').flush()

    def makefile(self, mode, bufsize):
        f = object.__getattribute__(self, '_orig').makefile(mode, bufsize)

        logfp = object.__getattribute__(self, '_logfp')
        cond = object.__getattribute__(self, '_cond')

        return fileobjectproxy(f, logfp, cond)

    def sendall(self, data, flags=0):
        cond = object.__getattribute__(self, '_cond')
        return cond.forward_write(self, 'sendall', data, flags)

    def _cond_close(self):
        object.__getattribute__(self, '_orig').shutdown(socket.SHUT_RDWR)


# We can't adjust __class__ on socket._fileobject, so define a proxy.
class fileobjectproxy:
    __slots__ = ('_orig', '_logfp', '_cond')

    def __init__(self, obj, logfp, condition_tracked):
        object.__setattr__(self, '_orig', obj)
        object.__setattr__(self, '_logfp', logfp)
        object.__setattr__(self, '_cond', condition_tracked)

    def __getattribute__(self, name):
        if name in (
            '_close',
            'read',
            'readline',
            'write',
            '_writelog',
            '_cond_close',
        ):
            return object.__getattribute__(self, name)

        return getattr(object.__getattribute__(self, '_orig'), name)

    def __delattr__(self, name):
        delattr(object.__getattribute__(self, '_orig'), name)

    def __setattr__(self, name, value):
        setattr(object.__getattribute__(self, '_orig'), name, value)

    def _writelog(self, msg):
        msg = msg.replace(b'\r', b'\\r').replace(b'\n', b'\\n')

        object.__getattribute__(self, '_logfp').write(msg)
        object.__getattribute__(self, '_logfp').write(b'\n')
        object.__getattribute__(self, '_logfp').flush()

    def _close(self):
        # We wrap an io.BufferedIO instance.
        self.raw._sock.shutdown(socket.SHUT_RDWR)

    def read(self, size=-1):
        cond = object.__getattribute__(self, '_cond')
        return cond.forward_read(self, 'read', size)

    def readline(self, size=-1):
        cond = object.__getattribute__(self, '_cond')
        return cond.forward_read(self, 'readline', size)

    def write(self, data):
        cond = object.__getattribute__(self, '_cond')
        return cond.forward_write(self, 'write', data)

    def _cond_close(self):
        self._close()


def process_bytes_config(value):
    parts = value.split(b',')
    integers = [int(v) for v in parts if v]
    return [v if v else None for v in integers]


def process_pattern_config(value):
    patterns = []
    for p in value.split(b','):
        if not p:
            p = None
        else:
            p = re.compile(p, re.DOTALL | re.MULTILINE)
        patterns.append(p)
    return patterns


def extsetup(ui):
    # Change the base HTTP server class so various events can be performed.
    # See SocketServer.BaseServer for how the specially named methods work.
    class badserver(server.MercurialHTTPServer):
        def __init__(self, ui, *args, **kwargs):
            self._ui = ui
            super(badserver, self).__init__(ui, *args, **kwargs)

            all_recv_bytes = self._ui.config(
                b'badserver', b'close-after-recv-bytes'
            )
            all_recv_bytes = process_bytes_config(all_recv_bytes)
            all_recv_pattern = self._ui.config(
                b'badserver', b'close-after-recv-patterns'
            )
            all_recv_pattern = process_pattern_config(all_recv_pattern)
            all_send_bytes = self._ui.config(
                b'badserver', b'close-after-send-bytes'
            )
            all_send_bytes = process_bytes_config(all_send_bytes)
            all_send_patterns = self._ui.config(
                b'badserver', b'close-after-send-patterns'
            )
            all_send_patterns = process_pattern_config(all_send_patterns)
            self._cond = ConditionTracker(
                all_recv_bytes,
                all_recv_pattern,
                all_send_bytes,
                all_send_patterns,
            )

            # Need to inherit object so super() works.
            class badrequesthandler(self.RequestHandlerClass, object):
                def send_header(self, name, value):
                    # Make headers deterministic to facilitate testing.
                    if name.lower() == 'date':
                        value = 'Fri, 14 Apr 2017 00:00:00 GMT'
                    elif name.lower() == 'server':
                        value = 'badhttpserver'

                    return super(badrequesthandler, self).send_header(
                        name, value
                    )

            self.RequestHandlerClass = badrequesthandler

        # Called to accept() a pending socket.
        def get_request(self):
            if self._ui.configbool(b'badserver', b'close-before-accept'):
                self.socket.close()

                # Tells the server to stop processing more requests.
                self.__shutdown_request = True

                # Simulate failure to stop processing this request.
                raise socket.error('close before accept')

            if self._ui.configbool(b'badserver', b'close-after-accept'):
                request, client_address = super(badserver, self).get_request()
                request.close()
                raise socket.error('close after accept')

            return super(badserver, self).get_request()

        # Does heavy lifting of processing a request. Invokes
        # self.finish_request() which calls self.RequestHandlerClass() which
        # is a hgweb.server._httprequesthandler.
        def process_request(self, socket, address):
            # Wrap socket in a proxy if we need to count bytes.
            self._cond.start_next_request()

            if self._cond.might_close():
                socket = socketproxy(
                    socket, self.errorlog, condition_tracked=self._cond
                )

            return super(badserver, self).process_request(socket, address)

    server.MercurialHTTPServer = badserver
