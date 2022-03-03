import unittest

from mercurial.hgweb import request as requestmod
from mercurial import error, pycompat

DEFAULT_ENV = {
    'REQUEST_METHOD': 'GET',
    'SERVER_NAME': 'testserver',
    'SERVER_PORT': '80',
    'SERVER_PROTOCOL': 'http',
    'wsgi.version': (1, 0),
    'wsgi.url_scheme': 'http',
    'wsgi.input': None,
    'wsgi.errors': None,
    'wsgi.multithread': False,
    'wsgi.multiprocess': True,
    'wsgi.run_once': False,
}


def parse(env, reponame=None, altbaseurl=None, extra=None):
    env = dict(env)
    env.update(extra or {})

    return requestmod.parserequestfromenv(
        env, reponame=reponame, altbaseurl=altbaseurl
    )


class ParseRequestTests(unittest.TestCase):
    def testdefault(self):
        r = parse(DEFAULT_ENV)
        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.method, b'GET')
        self.assertIsNone(r.remoteuser)
        self.assertIsNone(r.remotehost)
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)
        self.assertIsNone(r.reponame)
        self.assertEqual(r.querystring, b'')
        self.assertEqual(len(r.qsparams), 0)
        self.assertEqual(len(r.headers), 0)

    def testcustomport(self):
        r = parse(
            DEFAULT_ENV,
            extra={
                'SERVER_PORT': '8000',
            },
        )

        self.assertEqual(r.url, b'http://testserver:8000')
        self.assertEqual(r.baseurl, b'http://testserver:8000')
        self.assertEqual(r.advertisedurl, b'http://testserver:8000')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver:8000')

        r = parse(
            DEFAULT_ENV,
            extra={
                'SERVER_PORT': '4000',
                'wsgi.url_scheme': 'https',
            },
        )

        self.assertEqual(r.url, b'https://testserver:4000')
        self.assertEqual(r.baseurl, b'https://testserver:4000')
        self.assertEqual(r.advertisedurl, b'https://testserver:4000')
        self.assertEqual(r.advertisedbaseurl, b'https://testserver:4000')

    def testhttphost(self):
        r = parse(
            DEFAULT_ENV,
            extra={
                'HTTP_HOST': 'altserver',
            },
        )

        self.assertEqual(r.url, b'http://altserver')
        self.assertEqual(r.baseurl, b'http://altserver')
        self.assertEqual(r.advertisedurl, b'http://testserver')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')

    def testscriptname(self):
        r = parse(
            DEFAULT_ENV,
            extra={
                'SCRIPT_NAME': '',
            },
        )

        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)

        r = parse(
            DEFAULT_ENV,
            extra={
                'SCRIPT_NAME': '/script',
            },
        )

        self.assertEqual(r.url, b'http://testserver/script')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver/script')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'/script')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)

        r = parse(
            DEFAULT_ENV,
            extra={
                'SCRIPT_NAME': '/multiple words',
            },
        )

        self.assertEqual(r.url, b'http://testserver/multiple%20words')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver/multiple%20words')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'/multiple words')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)

    def testpathinfo(self):
        r = parse(
            DEFAULT_ENV,
            extra={
                'PATH_INFO': '',
            },
        )

        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [])
        self.assertEqual(r.dispatchpath, b'')

        r = parse(
            DEFAULT_ENV,
            extra={
                'PATH_INFO': '/pathinfo',
            },
        )

        self.assertEqual(r.url, b'http://testserver/pathinfo')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver/pathinfo')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [b'pathinfo'])
        self.assertEqual(r.dispatchpath, b'pathinfo')

        r = parse(
            DEFAULT_ENV,
            extra={
                'PATH_INFO': '/one/two/',
            },
        )

        self.assertEqual(r.url, b'http://testserver/one/two/')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver/one/two/')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [b'one', b'two'])
        self.assertEqual(r.dispatchpath, b'one/two')

    def testscriptandpathinfo(self):
        r = parse(
            DEFAULT_ENV,
            extra={
                'SCRIPT_NAME': '/script',
                'PATH_INFO': '/pathinfo',
            },
        )

        self.assertEqual(r.url, b'http://testserver/script/pathinfo')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver/script/pathinfo')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'/script')
        self.assertEqual(r.dispatchparts, [b'pathinfo'])
        self.assertEqual(r.dispatchpath, b'pathinfo')

        r = parse(
            DEFAULT_ENV,
            extra={
                'SCRIPT_NAME': '/script1/script2',
                'PATH_INFO': '/path1/path2',
            },
        )

        self.assertEqual(
            r.url, b'http://testserver/script1/script2/path1/path2'
        )
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(
            r.advertisedurl, b'http://testserver/script1/script2/path1/path2'
        )
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'/script1/script2')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')

        r = parse(
            DEFAULT_ENV,
            extra={
                'HTTP_HOST': 'hostserver',
                'SCRIPT_NAME': '/script',
                'PATH_INFO': '/pathinfo',
            },
        )

        self.assertEqual(r.url, b'http://hostserver/script/pathinfo')
        self.assertEqual(r.baseurl, b'http://hostserver')
        self.assertEqual(r.advertisedurl, b'http://testserver/script/pathinfo')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'/script')
        self.assertEqual(r.dispatchparts, [b'pathinfo'])
        self.assertEqual(r.dispatchpath, b'pathinfo')

    if not getattr(unittest.TestCase, 'assertRaisesRegex', False):
        # Python 3.7 deprecates the regex*p* version, but 2.7 lacks
        # the regex version.
        assertRaisesRegex = (  # camelcase-required
            unittest.TestCase.assertRaisesRegexp
        )

    def testreponame(self):
        """repository path components get stripped from URL."""

        with self.assertRaisesRegex(
            error.ProgrammingError, 'reponame requires PATH_INFO'
        ):
            parse(DEFAULT_ENV, reponame=b'repo')

        with self.assertRaisesRegex(
            error.ProgrammingError, 'PATH_INFO does not begin with repo ' 'name'
        ):
            parse(
                DEFAULT_ENV,
                reponame=b'repo',
                extra={
                    'PATH_INFO': '/pathinfo',
                },
            )

        with self.assertRaisesRegex(
            error.ProgrammingError, 'reponame prefix of PATH_INFO'
        ):
            parse(
                DEFAULT_ENV,
                reponame=b'repo',
                extra={
                    'PATH_INFO': '/repoextra/path',
                },
            )

        r = parse(
            DEFAULT_ENV,
            reponame=b'repo',
            extra={
                'PATH_INFO': '/repo/path1/path2',
            },
        )

        self.assertEqual(r.url, b'http://testserver/repo/path1/path2')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://testserver/repo/path1/path2')
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'/repo')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')
        self.assertEqual(r.reponame, b'repo')

        r = parse(
            DEFAULT_ENV,
            reponame=b'prefix/repo',
            extra={
                'PATH_INFO': '/prefix/repo/path1/path2',
            },
        )

        self.assertEqual(r.url, b'http://testserver/prefix/repo/path1/path2')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(
            r.advertisedurl, b'http://testserver/prefix/repo/path1/path2'
        )
        self.assertEqual(r.advertisedbaseurl, b'http://testserver')
        self.assertEqual(r.apppath, b'/prefix/repo')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')
        self.assertEqual(r.reponame, b'prefix/repo')

    def testaltbaseurl(self):
        # Simple hostname remap.
        r = parse(DEFAULT_ENV, altbaseurl=b'http://altserver')

        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://altserver')
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)
        self.assertIsNone(r.reponame)

        # With a custom port.
        r = parse(DEFAULT_ENV, altbaseurl=b'http://altserver:8000')
        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://altserver:8000')
        self.assertEqual(r.advertisedbaseurl, b'http://altserver:8000')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)
        self.assertIsNone(r.reponame)

        # With a changed protocol.
        r = parse(DEFAULT_ENV, altbaseurl=b'https://altserver')
        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'https://altserver')
        self.assertEqual(r.advertisedbaseurl, b'https://altserver')
        # URL scheme is defined as the actual scheme, not advertised.
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)
        self.assertIsNone(r.reponame)

        # Need to specify explicit port number for proper https:// alt URLs.
        r = parse(DEFAULT_ENV, altbaseurl=b'https://altserver:443')
        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'https://altserver')
        self.assertEqual(r.advertisedbaseurl, b'https://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)
        self.assertIsNone(r.reponame)

        # With only PATH_INFO defined.
        r = parse(
            DEFAULT_ENV,
            altbaseurl=b'http://altserver',
            extra={
                'PATH_INFO': '/path1/path2',
            },
        )
        self.assertEqual(r.url, b'http://testserver/path1/path2')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://altserver/path1/path2')
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')
        self.assertIsNone(r.reponame)

        # Path on alt URL.
        r = parse(DEFAULT_ENV, altbaseurl=b'http://altserver/altpath')
        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://altserver/altpath')
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'/altpath')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)
        self.assertIsNone(r.reponame)

        # With a trailing slash.
        r = parse(DEFAULT_ENV, altbaseurl=b'http://altserver/altpath/')
        self.assertEqual(r.url, b'http://testserver')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://altserver/altpath/')
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'/altpath/')
        self.assertEqual(r.dispatchparts, [])
        self.assertIsNone(r.dispatchpath)
        self.assertIsNone(r.reponame)

        # PATH_INFO + path on alt URL.
        r = parse(
            DEFAULT_ENV,
            altbaseurl=b'http://altserver/altpath',
            extra={
                'PATH_INFO': '/path1/path2',
            },
        )
        self.assertEqual(r.url, b'http://testserver/path1/path2')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(
            r.advertisedurl, b'http://altserver/altpath/path1/path2'
        )
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'/altpath')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')
        self.assertIsNone(r.reponame)

        # PATH_INFO + path on alt URL with trailing slash.
        r = parse(
            DEFAULT_ENV,
            altbaseurl=b'http://altserver/altpath/',
            extra={
                'PATH_INFO': '/path1/path2',
            },
        )
        self.assertEqual(r.url, b'http://testserver/path1/path2')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(
            r.advertisedurl, b'http://altserver/altpath//path1/path2'
        )
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'/altpath/')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')
        self.assertIsNone(r.reponame)

        # Local SCRIPT_NAME is ignored.
        r = parse(
            DEFAULT_ENV,
            altbaseurl=b'http://altserver',
            extra={
                'SCRIPT_NAME': '/script',
                'PATH_INFO': '/path1/path2',
            },
        )
        self.assertEqual(r.url, b'http://testserver/script/path1/path2')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(r.advertisedurl, b'http://altserver/path1/path2')
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')
        self.assertIsNone(r.reponame)

        # Use remote's path for script name, app path
        r = parse(
            DEFAULT_ENV,
            altbaseurl=b'http://altserver/altroot',
            extra={
                'SCRIPT_NAME': '/script',
                'PATH_INFO': '/path1/path2',
            },
        )
        self.assertEqual(r.url, b'http://testserver/script/path1/path2')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(
            r.advertisedurl, b'http://altserver/altroot/path1/path2'
        )
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.urlscheme, b'http')
        self.assertEqual(r.apppath, b'/altroot')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')
        self.assertIsNone(r.reponame)

        # reponame is factored in properly.
        r = parse(
            DEFAULT_ENV,
            reponame=b'repo',
            altbaseurl=b'http://altserver/altroot',
            extra={
                'SCRIPT_NAME': '/script',
                'PATH_INFO': '/repo/path1/path2',
            },
        )

        self.assertEqual(r.url, b'http://testserver/script/repo/path1/path2')
        self.assertEqual(r.baseurl, b'http://testserver')
        self.assertEqual(
            r.advertisedurl, b'http://altserver/altroot/repo/path1/path2'
        )
        self.assertEqual(r.advertisedbaseurl, b'http://altserver')
        self.assertEqual(r.apppath, b'/altroot/repo')
        self.assertEqual(r.dispatchparts, [b'path1', b'path2'])
        self.assertEqual(r.dispatchpath, b'path1/path2')
        self.assertEqual(r.reponame, b'repo')

    def testenvencoding(self):
        if pycompat.iswindows:
            # On Windows, we can't generally know which non-ASCII characters
            # are supported.
            r = parse(DEFAULT_ENV, extra={'foo': 'bar'})
            self.assertEqual(r.rawenv[b'foo'], b'bar')
        else:
            # Unix is byte-based. Therefore we test all possible bytes.
            b = b''.join(pycompat.bytechr(i) for i in range(256))
            r = parse(DEFAULT_ENV, extra={'foo': pycompat.fsdecode(b)})
            self.assertEqual(r.rawenv[b'foo'], b)


if __name__ == '__main__':
    import silenttestrunner

    silenttestrunner.main(__name__)
