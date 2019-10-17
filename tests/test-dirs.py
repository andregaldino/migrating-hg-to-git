from __future__ import absolute_import

import unittest

import silenttestrunner

from mercurial import util


class dirstests(unittest.TestCase):
    def testdirs(self):
        for case, want in [
            (b'a/a/a', [b'a', b'a/a', b'']),
            (b'alpha/beta/gamma', [b'', b'alpha', b'alpha/beta']),
        ]:
            d = util.dirs({})
            d.addpath(case)
            self.assertEqual(sorted(d), sorted(want))

    def testinvalid(self):
        with self.assertRaises(ValueError):
            d = util.dirs({})
            d.addpath(b'a//b')


if __name__ == '__main__':
    silenttestrunner.main(__name__)
