# hgweb/request.py - An http request from either CGI or the standalone server.
#
# Copyright 21 May 2005 - (c) 2005 Jake Edge <jake@edge2.net>
# Copyright 2005, 2006 Matt Mackall <mpm@selenic.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import errno
import socket
import wsgiref.headers as wsgiheaders
#import wsgiref.validate

from .common import (
    ErrorResponse,
    HTTP_NOT_MODIFIED,
    statusmessage,
)

from ..thirdparty import (
    attr,
)
from .. import (
    error,
    pycompat,
    util,
)

@attr.s(frozen=True)
class parsedrequest(object):
    """Represents a parsed WSGI request.

    Contains both parsed parameters as well as a handle on the input stream.
    """

    # Request method.
    method = attr.ib()
    # Full URL for this request.
    url = attr.ib()
    # URL without any path components. Just <proto>://<host><port>.
    baseurl = attr.ib()
    # Advertised URL. Like ``url`` and ``baseurl`` but uses SERVER_NAME instead
    # of HTTP: Host header for hostname. This is likely what clients used.
    advertisedurl = attr.ib()
    advertisedbaseurl = attr.ib()
    # WSGI application path.
    apppath = attr.ib()
    # List of path parts to be used for dispatch.
    dispatchparts = attr.ib()
    # URL path component (no query string) used for dispatch.
    dispatchpath = attr.ib()
    # Whether there is a path component to this request. This can be true
    # when ``dispatchpath`` is empty due to REPO_NAME muckery.
    havepathinfo = attr.ib()
    # Raw query string (part after "?" in URL).
    querystring = attr.ib()
    # List of 2-tuples of query string arguments.
    querystringlist = attr.ib()
    # Dict of query string arguments. Values are lists with at least 1 item.
    querystringdict = attr.ib()
    # wsgiref.headers.Headers instance. Operates like a dict with case
    # insensitive keys.
    headers = attr.ib()
    # Request body input stream.
    bodyfh = attr.ib()

def parserequestfromenv(env, bodyfh):
    """Parse URL components from environment variables.

    WSGI defines request attributes via environment variables. This function
    parses the environment variables into a data structure.
    """
    # PEP-0333 defines the WSGI spec and is a useful reference for this code.

    # We first validate that the incoming object conforms with the WSGI spec.
    # We only want to be dealing with spec-conforming WSGI implementations.
    # TODO enable this once we fix internal violations.
    #wsgiref.validate.check_environ(env)

    # PEP-0333 states that environment keys and values are native strings
    # (bytes on Python 2 and str on Python 3). The code points for the Unicode
    # strings on Python 3 must be between \00000-\000FF. We deal with bytes
    # in Mercurial, so mass convert string keys and values to bytes.
    if pycompat.ispy3:
        env = {k.encode('latin-1'): v for k, v in env.iteritems()}
        env = {k: v.encode('latin-1') if isinstance(v, str) else v
               for k, v in env.iteritems()}

    # https://www.python.org/dev/peps/pep-0333/#environ-variables defines
    # the environment variables.
    # https://www.python.org/dev/peps/pep-0333/#url-reconstruction defines
    # how URLs are reconstructed.
    fullurl = env['wsgi.url_scheme'] + '://'
    advertisedfullurl = fullurl

    def addport(s):
        if env['wsgi.url_scheme'] == 'https':
            if env['SERVER_PORT'] != '443':
                s += ':' + env['SERVER_PORT']
        else:
            if env['SERVER_PORT'] != '80':
                s += ':' + env['SERVER_PORT']

        return s

    if env.get('HTTP_HOST'):
        fullurl += env['HTTP_HOST']
    else:
        fullurl += env['SERVER_NAME']
        fullurl = addport(fullurl)

    advertisedfullurl += env['SERVER_NAME']
    advertisedfullurl = addport(advertisedfullurl)

    baseurl = fullurl
    advertisedbaseurl = advertisedfullurl

    fullurl += util.urlreq.quote(env.get('SCRIPT_NAME', ''))
    advertisedfullurl += util.urlreq.quote(env.get('SCRIPT_NAME', ''))
    fullurl += util.urlreq.quote(env.get('PATH_INFO', ''))
    advertisedfullurl += util.urlreq.quote(env.get('PATH_INFO', ''))

    if env.get('QUERY_STRING'):
        fullurl += '?' + env['QUERY_STRING']
        advertisedfullurl += '?' + env['QUERY_STRING']

    # When dispatching requests, we look at the URL components (PATH_INFO
    # and QUERY_STRING) after the application root (SCRIPT_NAME). But hgwebdir
    # has the concept of "virtual" repositories. This is defined via REPO_NAME.
    # If REPO_NAME is defined, we append it to SCRIPT_NAME to form a new app
    # root. We also exclude its path components from PATH_INFO when resolving
    # the dispatch path.

    apppath = env['SCRIPT_NAME']

    if env.get('REPO_NAME'):
        if not apppath.endswith('/'):
            apppath += '/'

        apppath += env.get('REPO_NAME')

    if 'PATH_INFO' in env:
        dispatchparts = env['PATH_INFO'].strip('/').split('/')

        # Strip out repo parts.
        repoparts = env.get('REPO_NAME', '').split('/')
        if dispatchparts[:len(repoparts)] == repoparts:
            dispatchparts = dispatchparts[len(repoparts):]
    else:
        dispatchparts = []

    dispatchpath = '/'.join(dispatchparts)

    querystring = env.get('QUERY_STRING', '')

    # We store as a list so we have ordering information. We also store as
    # a dict to facilitate fast lookup.
    querystringlist = util.urlreq.parseqsl(querystring, keep_blank_values=True)

    querystringdict = {}
    for k, v in querystringlist:
        if k in querystringdict:
            querystringdict[k].append(v)
        else:
            querystringdict[k] = [v]

    # HTTP_* keys contain HTTP request headers. The Headers structure should
    # perform case normalization for us. We just rewrite underscore to dash
    # so keys match what likely went over the wire.
    headers = []
    for k, v in env.iteritems():
        if k.startswith('HTTP_'):
            headers.append((k[len('HTTP_'):].replace('_', '-'), v))

    headers = wsgiheaders.Headers(headers)

    # This is kind of a lie because the HTTP header wasn't explicitly
    # sent. But for all intents and purposes it should be OK to lie about
    # this, since a consumer will either either value to determine how many
    # bytes are available to read.
    if 'CONTENT_LENGTH' in env and 'HTTP_CONTENT_LENGTH' not in env:
        headers['Content-Length'] = env['CONTENT_LENGTH']

    # TODO do this once we remove wsgirequest.inp, otherwise we could have
    # multiple readers from the underlying input stream.
    #bodyfh = env['wsgi.input']
    #if 'Content-Length' in headers:
    #    bodyfh = util.cappedreader(bodyfh, int(headers['Content-Length']))

    return parsedrequest(method=env['REQUEST_METHOD'],
                         url=fullurl, baseurl=baseurl,
                         advertisedurl=advertisedfullurl,
                         advertisedbaseurl=advertisedbaseurl,
                         apppath=apppath,
                         dispatchparts=dispatchparts, dispatchpath=dispatchpath,
                         havepathinfo='PATH_INFO' in env,
                         querystring=querystring,
                         querystringlist=querystringlist,
                         querystringdict=querystringdict,
                         headers=headers,
                         bodyfh=bodyfh)

class wsgiresponse(object):
    """Represents a response to a WSGI request.

    A response consists of a status line, headers, and a body.

    Consumers must populate the ``status`` and ``headers`` fields and
    make a call to a ``setbody*()`` method before the response can be
    issued.

    When it is time to start sending the response over the wire,
    ``sendresponse()`` is called. It handles emitting the header portion
    of the response message. It then yields chunks of body data to be
    written to the peer. Typically, the WSGI application itself calls
    and returns the value from ``sendresponse()``.
    """

    def __init__(self, req, startresponse):
        """Create an empty response tied to a specific request.

        ``req`` is a ``parsedrequest``. ``startresponse`` is the
        ``start_response`` function passed to the WSGI application.
        """
        self._req = req
        self._startresponse = startresponse

        self.status = None
        self.headers = wsgiheaders.Headers([])

        self._bodybytes = None
        self._bodygen = None
        self._started = False

    def setbodybytes(self, b):
        """Define the response body as static bytes."""
        if self._bodybytes is not None or self._bodygen is not None:
            raise error.ProgrammingError('cannot define body multiple times')

        self._bodybytes = b
        self.headers['Content-Length'] = '%d' % len(b)

    def setbodygen(self, gen):
        """Define the response body as a generator of bytes."""
        if self._bodybytes is not None or self._bodygen is not None:
            raise error.ProgrammingError('cannot define body multiple times')

        self._bodygen = gen

    def sendresponse(self):
        """Send the generated response to the client.

        Before this is called, ``status`` must be set and one of
        ``setbodybytes()`` or ``setbodygen()`` must be called.

        Calling this method multiple times is not allowed.
        """
        if self._started:
            raise error.ProgrammingError('sendresponse() called multiple times')

        self._started = True

        if not self.status:
            raise error.ProgrammingError('status line not defined')

        if self._bodybytes is None and self._bodygen is None:
            raise error.ProgrammingError('response body not defined')

        # Various HTTP clients (notably httplib) won't read the HTTP response
        # until the HTTP request has been sent in full. If servers (us) send a
        # response before the HTTP request has been fully sent, the connection
        # may deadlock because neither end is reading.
        #
        # We work around this by "draining" the request data before
        # sending any response in some conditions.
        drain = False
        close = False

        # If the client sent Expect: 100-continue, we assume it is smart enough
        # to deal with the server sending a response before reading the request.
        # (httplib doesn't do this.)
        if self._req.headers.get('Expect', '').lower() == '100-continue':
            pass
        # Only tend to request methods that have bodies. Strictly speaking,
        # we should sniff for a body. But this is fine for our existing
        # WSGI applications.
        elif self._req.method not in ('POST', 'PUT'):
            pass
        else:
            # If we don't know how much data to read, there's no guarantee
            # that we can drain the request responsibly. The WSGI
            # specification only says that servers *should* ensure the
            # input stream doesn't overrun the actual request. So there's
            # no guarantee that reading until EOF won't corrupt the stream
            # state.
            if not isinstance(self._req.bodyfh, util.cappedreader):
                close = True
            else:
                # We /could/ only drain certain HTTP response codes. But 200 and
                # non-200 wire protocol responses both require draining. Since
                # we have a capped reader in place for all situations where we
                # drain, it is safe to read from that stream. We'll either do
                # a drain or no-op if we're already at EOF.
                drain = True

        if close:
            self.headers['Connection'] = 'Close'

        if drain:
            assert isinstance(self._req.bodyfh, util.cappedreader)
            while True:
                chunk = self._req.bodyfh.read(32768)
                if not chunk:
                    break

        self._startresponse(pycompat.sysstr(self.status), self.headers.items())
        if self._bodybytes:
            yield self._bodybytes
        elif self._bodygen:
            for chunk in self._bodygen:
                yield chunk
        else:
            error.ProgrammingError('do not know how to send body')

class wsgirequest(object):
    """Higher-level API for a WSGI request.

    WSGI applications are invoked with 2 arguments. They are used to
    instantiate instances of this class, which provides higher-level APIs
    for obtaining request parameters, writing HTTP output, etc.
    """
    def __init__(self, wsgienv, start_response):
        version = wsgienv[r'wsgi.version']
        if (version < (1, 0)) or (version >= (2, 0)):
            raise RuntimeError("Unknown and unsupported WSGI version %d.%d"
                               % version)

        inp = wsgienv[r'wsgi.input']

        if r'HTTP_CONTENT_LENGTH' in wsgienv:
            inp = util.cappedreader(inp, int(wsgienv[r'HTTP_CONTENT_LENGTH']))
        elif r'CONTENT_LENGTH' in wsgienv:
            inp = util.cappedreader(inp, int(wsgienv[r'CONTENT_LENGTH']))

        self.err = wsgienv[r'wsgi.errors']
        self.threaded = wsgienv[r'wsgi.multithread']
        self.multiprocess = wsgienv[r'wsgi.multiprocess']
        self.run_once = wsgienv[r'wsgi.run_once']
        self.env = wsgienv
        self.req = parserequestfromenv(wsgienv, inp)
        self.form = self.req.querystringdict
        self.res = wsgiresponse(self.req, start_response)
        self._start_response = start_response
        self.server_write = None
        self.headers = []

    def respond(self, status, type, filename=None, body=None):
        if not isinstance(type, str):
            type = pycompat.sysstr(type)
        if self._start_response is not None:
            self.headers.append((r'Content-Type', type))
            if filename:
                filename = (filename.rpartition('/')[-1]
                            .replace('\\', '\\\\').replace('"', '\\"'))
                self.headers.append(('Content-Disposition',
                                     'inline; filename="%s"' % filename))
            if body is not None:
                self.headers.append((r'Content-Length', str(len(body))))

            for k, v in self.headers:
                if not isinstance(v, str):
                    raise TypeError('header value must be string: %r' % (v,))

            if isinstance(status, ErrorResponse):
                self.headers.extend(status.headers)
                if status.code == HTTP_NOT_MODIFIED:
                    # RFC 2616 Section 10.3.5: 304 Not Modified has cases where
                    # it MUST NOT include any headers other than these and no
                    # body
                    self.headers = [(k, v) for (k, v) in self.headers if
                                    k in ('Date', 'ETag', 'Expires',
                                          'Cache-Control', 'Vary')]
                status = statusmessage(status.code, pycompat.bytestr(status))
            elif status == 200:
                status = '200 Script output follows'
            elif isinstance(status, int):
                status = statusmessage(status)

            # Various HTTP clients (notably httplib) won't read the HTTP
            # response until the HTTP request has been sent in full. If servers
            # (us) send a response before the HTTP request has been fully sent,
            # the connection may deadlock because neither end is reading.
            #
            # We work around this by "draining" the request data before
            # sending any response in some conditions.
            drain = False
            close = False

            # If the client sent Expect: 100-continue, we assume it is smart
            # enough to deal with the server sending a response before reading
            # the request. (httplib doesn't do this.)
            if self.env.get(r'HTTP_EXPECT', r'').lower() == r'100-continue':
                pass
            # Only tend to request methods that have bodies. Strictly speaking,
            # we should sniff for a body. But this is fine for our existing
            # WSGI applications.
            elif self.env[r'REQUEST_METHOD'] not in (r'POST', r'PUT'):
                pass
            else:
                # If we don't know how much data to read, there's no guarantee
                # that we can drain the request responsibly. The WSGI
                # specification only says that servers *should* ensure the
                # input stream doesn't overrun the actual request. So there's
                # no guarantee that reading until EOF won't corrupt the stream
                # state.
                if not isinstance(self.req.bodyfh, util.cappedreader):
                    close = True
                else:
                    # We /could/ only drain certain HTTP response codes. But 200
                    # and non-200 wire protocol responses both require draining.
                    # Since we have a capped reader in place for all situations
                    # where we drain, it is safe to read from that stream. We'll
                    # either do a drain or no-op if we're already at EOF.
                    drain = True

            if close:
                self.headers.append((r'Connection', r'Close'))

            if drain:
                assert isinstance(self.req.bodyfh, util.cappedreader)
                while True:
                    chunk = self.req.bodyfh.read(32768)
                    if not chunk:
                        break

            self.server_write = self._start_response(
                pycompat.sysstr(status), self.headers)
            self._start_response = None
            self.headers = []
        if body is not None:
            self.write(body)
            self.server_write = None

    def write(self, thing):
        if thing:
            try:
                self.server_write(thing)
            except socket.error as inst:
                if inst[0] != errno.ECONNRESET:
                    raise

    def flush(self):
        return None

def wsgiapplication(app_maker):
    '''For compatibility with old CGI scripts. A plain hgweb() or hgwebdir()
    can and should now be used as a WSGI application.'''
    application = app_maker()
    def run_wsgi(env, respond):
        return application(env, respond)
    return run_wsgi
