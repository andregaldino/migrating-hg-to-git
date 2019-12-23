from __future__ import absolute_import
import unittest

try:
    from mercurial import rustext

    rustext.__name__  # trigger immediate actual import
except ImportError:
    rustext = None
else:
    from mercurial.rustext import revlog

from mercurial.testing import revlog as revlogtesting


@unittest.skipIf(
    rustext is None, "rustext module revlog relies on is not available",
)
class RustRevlogIndexTest(revlogtesting.RevlogBasedTestBase):
    def test_heads(self):
        idx = self.parseindex()
        rustidx = revlog.MixedIndex(idx)
        self.assertEqual(rustidx.headrevs(), idx.headrevs())

    def test_len(self):
        idx = self.parseindex()
        rustidx = revlog.MixedIndex(idx)
        self.assertEqual(len(rustidx), len(idx))


if __name__ == '__main__':
    import silenttestrunner

    silenttestrunner.main(__name__)
