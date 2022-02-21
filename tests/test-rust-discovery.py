import unittest

from mercurial import policy

PartialDiscovery = policy.importrust('discovery', member='PartialDiscovery')

try:
    from mercurial.cext import parsers as cparsers
except ImportError:
    cparsers = None

# picked from test-parse-index2, copied rather than imported
# so that it stays stable even if test-parse-index2 changes or disappears.
data_non_inlined = (
    b'\x00\x00\x00\x01\x00\x00\x00\x00\x00\x01D\x19'
    b'\x00\x07e\x12\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\xff\xff'
    b'\xff\xff\xff\xff\xd1\xf4\xbb\xb0\xbe\xfc\x13\xbd\x8c\xd3\x9d'
    b'\x0f\xcd\xd9;\x8c\x07\x8cJ/\x00\x00\x00\x00\x00\x00\x00\x00\x00'
    b'\x00\x00\x00\x00\x00\x00\x01D\x19\x00\x00\x00\x00\x00\xdf\x00'
    b'\x00\x01q\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\xff'
    b'\xff\xff\xff\xc1\x12\xb9\x04\x96\xa4Z1t\x91\xdfsJ\x90\xf0\x9bh'
    b'\x07l&\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
    b'\x00\x01D\xf8\x00\x00\x00\x00\x01\x1b\x00\x00\x01\xb8\x00\x00'
    b'\x00\x01\x00\x00\x00\x02\x00\x00\x00\x01\xff\xff\xff\xff\x02\n'
    b'\x0e\xc6&\xa1\x92\xae6\x0b\x02i\xfe-\xe5\xbao\x05\xd1\xe7\x00'
    b'\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01F'
    b'\x13\x00\x00\x00\x00\x01\xec\x00\x00\x03\x06\x00\x00\x00\x01'
    b'\x00\x00\x00\x03\x00\x00\x00\x02\xff\xff\xff\xff\x12\xcb\xeby1'
    b'\xb6\r\x98B\xcb\x07\xbd`\x8f\x92\xd9\xc4\x84\xbdK\x00\x00\x00'
    b'\x00\x00\x00\x00\x00\x00\x00\x00\x00'
)


class fakechangelog:
    def __init__(self, idx):
        self.index = idx


class fakerepo:
    def __init__(self, idx):
        """Just make so that self.changelog.index is the given idx."""
        self.changelog = fakechangelog(idx)


@unittest.skipIf(
    PartialDiscovery is None or cparsers is None,
    "rustext or the C Extension parsers module "
    "discovery relies on is not available",
)
class rustdiscoverytest(unittest.TestCase):
    """Test the correctness of binding to Rust code.

    This test is merely for the binding to Rust itself: extraction of
    Python variable, giving back the results etc.

    It is not meant to test the algorithmic correctness of the provided
    methods. Hence the very simple embedded index data is good enough.

    Algorithmic correctness is asserted by the Rust unit tests.
    """

    def parseindex(self):
        return cparsers.parse_index2(data_non_inlined, False)[0]

    def repo(self):
        return fakerepo(self.parseindex())

    def testindex(self):
        idx = self.parseindex()
        # checking our assumptions about the index binary data:
        self.assertEqual(
            {i: (r[5], r[6]) for i, r in enumerate(idx)},
            {0: (-1, -1), 1: (0, -1), 2: (1, -1), 3: (2, -1)},
        )

    def testaddcommonsmissings(self):
        disco = PartialDiscovery(self.repo(), [3], True)
        self.assertFalse(disco.hasinfo())
        self.assertFalse(disco.iscomplete())

        disco.addcommons([1])
        self.assertTrue(disco.hasinfo())
        self.assertFalse(disco.iscomplete())

        disco.addmissings([2])
        self.assertTrue(disco.hasinfo())
        self.assertTrue(disco.iscomplete())

        self.assertEqual(disco.commonheads(), {1})

    def testaddmissingsstats(self):
        disco = PartialDiscovery(self.repo(), [3], True)
        self.assertIsNone(disco.stats()['undecided'], None)

        disco.addmissings([2])
        self.assertEqual(disco.stats()['undecided'], 2)

    def testaddinfocommonfirst(self):
        disco = PartialDiscovery(self.repo(), [3], True)
        disco.addinfo([(1, True), (2, False)])
        self.assertTrue(disco.hasinfo())
        self.assertTrue(disco.iscomplete())
        self.assertEqual(disco.commonheads(), {1})

    def testaddinfomissingfirst(self):
        disco = PartialDiscovery(self.repo(), [3], True)
        disco.addinfo([(2, False), (1, True)])
        self.assertTrue(disco.hasinfo())
        self.assertTrue(disco.iscomplete())
        self.assertEqual(disco.commonheads(), {1})

    def testinitnorandom(self):
        PartialDiscovery(self.repo(), [3], True, randomize=False)


if __name__ == '__main__':
    import silenttestrunner

    silenttestrunner.main(__name__)
