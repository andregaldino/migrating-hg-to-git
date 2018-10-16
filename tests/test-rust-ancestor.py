from __future__ import absolute_import
import unittest

try:
    from mercurial import rustext
except ImportError:
    rustext = None

try:
    from mercurial.cext import parsers as cparsers
except ImportError:
    cparsers = None

@unittest.skipIf(rustext is None or cparsers is None,
                 "rustext.ancestor or the C Extension parsers module "
                 "it relies on is not available")
class rustancestorstest(unittest.TestCase):
    """Test the correctness of binding to Rust code.

    This test is merely for the binding to Rust itself: extraction of
    Python variable, giving back the results etc.

    It is not meant to test the algorithmic correctness of the operations
    on ancestors it provides. Hence the very simple embedded index data is
    good enough.

    Algorithmic correctness is asserted by the Rust unit tests.
    """

    def testmodule(self):
        self.assertTrue('DAG' in rustext.ancestor.__doc__)

    def testgrapherror(self):
        self.assertTrue('GraphError' in dir(rustext))


if __name__ == '__main__':
    import silenttestrunner
    silenttestrunner.main(__name__)
