# Tests to ensure that sha1dc.sha1 is exactly a drop-in for
# hashlib.sha1 for our needs.

import hashlib
import unittest

import silenttestrunner

try:
    from mercurial.thirdparty import sha1dc
except ImportError:
    sha1dc = None


class hashertestsbase:
    def test_basic_hash(self):
        h = self.hasher()
        h.update(b'foo')
        self.assertEqual(
            '0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33', h.hexdigest()
        )
        h.update(b'bar')
        self.assertEqual(
            '8843d7f92416211de9ebb963ff4ce28125932878', h.hexdigest()
        )

    def test_copy_hasher(self):
        h = self.hasher()
        h.update(b'foo')
        h2 = h.copy()
        h.update(b'baz')
        h2.update(b'bar')
        self.assertEqual(
            '21eb6533733a5e4763acacd1d45a60c2e0e404e1', h.hexdigest()
        )
        self.assertEqual(
            '8843d7f92416211de9ebb963ff4ce28125932878', h2.hexdigest()
        )

    def test_init_hasher(self):
        h = self.hasher(b'initial string')
        self.assertEqual(
            b'\xc9y|n\x1f3S\xa4:\xbaJ\xca,\xc1\x1a\x9e\xb8\xd8\xdd\x86',
            h.digest(),
        )

    def test_bytes_like_types(self):
        h = self.hasher()
        h.update(bytearray(b'foo'))
        h.update(memoryview(b'baz'))
        self.assertEqual(
            '21eb6533733a5e4763acacd1d45a60c2e0e404e1', h.hexdigest()
        )

        h = self.hasher(bytearray(b'foo'))
        h.update(b'baz')
        self.assertEqual(
            '21eb6533733a5e4763acacd1d45a60c2e0e404e1', h.hexdigest()
        )

        h = self.hasher(memoryview(b'foo'))
        h.update(b'baz')
        self.assertEqual(
            '21eb6533733a5e4763acacd1d45a60c2e0e404e1', h.hexdigest()
        )


class hashlibtests(unittest.TestCase, hashertestsbase):
    hasher = hashlib.sha1


if sha1dc:

    class sha1dctests(unittest.TestCase, hashertestsbase):
        hasher = sha1dc.sha1


if __name__ == '__main__':
    silenttestrunner.main(__name__)
