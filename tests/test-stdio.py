#!/usr/bin/env python
"""
Tests the buffering behavior of stdio streams in `mercurial.utils.procutil`.
"""
from __future__ import absolute_import

import contextlib
import os
import subprocess
import sys
import unittest

from mercurial import pycompat


CHILD_PROCESS = r'''
import os

from mercurial import dispatch
from mercurial.utils import procutil

dispatch.initstdio()
procutil.stdout.write(b'aaa')
os.write(procutil.stdout.fileno(), b'[written aaa]')
procutil.stdout.write(b'bbb\n')
os.write(procutil.stdout.fileno(), b'[written bbb\\n]')
'''
UNBUFFERED = b'aaa[written aaa]bbb\n[written bbb\\n]'
LINE_BUFFERED = b'[written aaa]aaabbb\n[written bbb\\n]'
FULLY_BUFFERED = b'[written aaa][written bbb\\n]aaabbb\n'


@contextlib.contextmanager
def _closing(fds):
    try:
        yield
    finally:
        for fd in fds:
            try:
                os.close(fd)
            except EnvironmentError:
                pass


@contextlib.contextmanager
def _pipes():
    rwpair = os.pipe()
    with _closing(rwpair):
        yield rwpair


@contextlib.contextmanager
def _ptys():
    if pycompat.iswindows:
        raise unittest.SkipTest("PTYs are not supported on Windows")
    import pty
    import tty

    rwpair = pty.openpty()
    with _closing(rwpair):
        tty.setraw(rwpair[0])
        yield rwpair


class TestStdout(unittest.TestCase):
    def _test(self, rwpair_generator, expected_output, python_args=[]):
        with rwpair_generator() as (stdout_receiver, child_stdout), open(
            os.devnull, 'rb'
        ) as child_stdin:
            proc = subprocess.Popen(
                [sys.executable] + python_args + ['-c', CHILD_PROCESS],
                stdin=child_stdin,
                stdout=child_stdout,
                stderr=None,
            )
            retcode = proc.wait()
            self.assertEqual(retcode, 0)
            self.assertEqual(os.read(stdout_receiver, 1024), expected_output)

    def test_stdout_pipes(self):
        self._test(_pipes, FULLY_BUFFERED)

    def test_stdout_ptys(self):
        self._test(_ptys, LINE_BUFFERED)

    def test_stdout_pipes_unbuffered(self):
        self._test(_pipes, UNBUFFERED, python_args=['-u'])

    def test_stdout_ptys_unbuffered(self):
        self._test(_ptys, UNBUFFERED, python_args=['-u'])

    # On Windows, test_stdout_ptys wouldn't pass, but it's skipped anyway.
    if not pycompat.ispy3 and not pycompat.iswindows:
        # On Python 2 on non-Windows, we manually open stdout in line-buffered
        # mode if connected to a TTY. We should check if Python was configured
        # to use unbuffered stdout, but it's hard to do that.
        test_stdout_ptys_unbuffered = unittest.expectedFailure(
            test_stdout_ptys_unbuffered
        )


if __name__ == '__main__':
    import silenttestrunner

    silenttestrunner.main(__name__)
