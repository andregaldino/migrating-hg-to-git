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
procutil.{stream}.write(b'aaa')
os.write(procutil.{stream}.fileno(), b'[written aaa]')
procutil.{stream}.write(b'bbb\n')
os.write(procutil.{stream}.fileno(), b'[written bbb\\n]')
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


class TestStdio(unittest.TestCase):
    def _test(self, stream, rwpair_generator, expected_output, python_args=[]):
        assert stream in ('stdout', 'stderr')
        with rwpair_generator() as (stream_receiver, child_stream), open(
            os.devnull, 'rb'
        ) as child_stdin:
            proc = subprocess.Popen(
                [sys.executable]
                + python_args
                + ['-c', CHILD_PROCESS.format(stream=stream)],
                stdin=child_stdin,
                stdout=child_stream if stream == 'stdout' else None,
                stderr=child_stream if stream == 'stderr' else None,
            )
            retcode = proc.wait()
            self.assertEqual(retcode, 0)
            self.assertEqual(os.read(stream_receiver, 1024), expected_output)

    def test_stdout_pipes(self):
        self._test('stdout', _pipes, FULLY_BUFFERED)

    def test_stdout_ptys(self):
        self._test('stdout', _ptys, LINE_BUFFERED)

    def test_stdout_pipes_unbuffered(self):
        self._test('stdout', _pipes, UNBUFFERED, python_args=['-u'])

    def test_stdout_ptys_unbuffered(self):
        self._test('stdout', _ptys, UNBUFFERED, python_args=['-u'])

    if not pycompat.ispy3 and not pycompat.iswindows:
        # On Python 2 on non-Windows, we manually open stdout in line-buffered
        # mode if connected to a TTY. We should check if Python was configured
        # to use unbuffered stdout, but it's hard to do that.
        test_stdout_ptys_unbuffered = unittest.expectedFailure(
            test_stdout_ptys_unbuffered
        )

    def test_stderr_pipes(self):
        self._test('stderr', _pipes, UNBUFFERED)

    def test_stderr_ptys(self):
        self._test('stderr', _ptys, UNBUFFERED)

    def test_stderr_pipes_unbuffered(self):
        self._test('stderr', _pipes, UNBUFFERED, python_args=['-u'])

    def test_stderr_ptys_unbuffered(self):
        self._test('stderr', _ptys, UNBUFFERED, python_args=['-u'])


if __name__ == '__main__':
    import silenttestrunner

    silenttestrunner.main(__name__)