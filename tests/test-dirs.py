import unittest

import silenttestrunner

from mercurial import pathutil


class dirstests(unittest.TestCase):
    def testdirs(self):
        for case, want in [
            (b'a/a/a', [b'a', b'a/a', b'']),
            (b'alpha/beta/gamma', [b'', b'alpha', b'alpha/beta']),
        ]:
            d = pathutil.dirs([])
            d.addpath(case)
            self.assertEqual(sorted(d), sorted(want))

    def testinvalid(self):
        with self.assertRaises(ValueError):
            d = pathutil.dirs([])
            d.addpath(b'a//b')


if __name__ == '__main__':
    silenttestrunner.main(__name__)
