import unittest

from mercurial.utils import urlutil


class ParseRequestTests(unittest.TestCase):
    def testparse(self):

        self.assertEqual(
            urlutil.parseurl(b'http://example.com/no/anchor'),
            (b'http://example.com/no/anchor', (None, [])),
        )
        self.assertEqual(
            urlutil.parseurl(b'http://example.com/an/anchor#foo'),
            (b'http://example.com/an/anchor', (b'foo', [])),
        )
        self.assertEqual(
            urlutil.parseurl(
                b'http://example.com/no/anchor/branches', [b'foo']
            ),
            (b'http://example.com/no/anchor/branches', (None, [b'foo'])),
        )
        self.assertEqual(
            urlutil.parseurl(
                b'http://example.com/an/anchor/branches#bar', [b'foo']
            ),
            (b'http://example.com/an/anchor/branches', (b'bar', [b'foo'])),
        )
        self.assertEqual(
            urlutil.parseurl(
                b'http://example.com/an/anchor/branches-None#foo', None
            ),
            (b'http://example.com/an/anchor/branches-None', (b'foo', [])),
        )
        self.assertEqual(
            urlutil.parseurl(b'http://example.com/'),
            (b'http://example.com/', (None, [])),
        )
        self.assertEqual(
            urlutil.parseurl(b'http://example.com'),
            (b'http://example.com/', (None, [])),
        )
        self.assertEqual(
            urlutil.parseurl(b'http://example.com#foo'),
            (b'http://example.com/', (b'foo', [])),
        )


if __name__ == '__main__':
    import silenttestrunner

    silenttestrunner.main(__name__)
