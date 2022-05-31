#!/usr/bin/env python
"""
Tests the buffering behavior of stdio streams in `mercurial.utils.procutil`.
"""

import contextlib
import errno
import os
import pickle
import signal
import subprocess
import sys
import tempfile
import unittest

from mercurial import pycompat, util


TEST_BUFFERING_CHILD_SCRIPT = r'''
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


TEST_LARGE_WRITE_CHILD_SCRIPT = r'''
import os
import signal
import sys

from mercurial import dispatch
from mercurial.utils import procutil

signal.signal(signal.SIGINT, lambda *x: None)
dispatch.initstdio()
write_result = procutil.{stream}.write(b'x' * 1048576)
with os.fdopen(
    os.open({write_result_fn!r}, os.O_WRONLY | getattr(os, 'O_TEMPORARY', 0)),
    'w',
) as write_result_f:
    write_result_f.write(str(write_result))
'''


TEST_BROKEN_PIPE_CHILD_SCRIPT = r'''
import os
import pickle

from mercurial import dispatch
from mercurial.utils import procutil

dispatch.initstdio()
procutil.stdin.read(1)  # wait until parent process closed pipe
try:
    procutil.{stream}.write(b'test')
    procutil.{stream}.flush()
except EnvironmentError as e:
    with os.fdopen(
        os.open(
            {err_fn!r},
            os.O_WRONLY
            | getattr(os, 'O_BINARY', 0)
            | getattr(os, 'O_TEMPORARY', 0),
        ),
        'wb',
    ) as err_f:
        pickle.dump(e, err_f)
# Exit early to suppress further broken pipe errors at interpreter shutdown.
os._exit(0)
'''


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


# In the following, we set the FDs non-inheritable mainly to make it possible
# for tests to close the receiving end of the pipe / PTYs.


@contextlib.contextmanager
def _devnull():
    devnull = os.open(os.devnull, os.O_WRONLY)
    # We don't have a receiving end, so it's not worth the effort on Python 2
    # on Windows to make the FD non-inheritable.
    with _closing([devnull]):
        yield (None, devnull)


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


def _readall(fd, buffer_size, initial_buf=None):
    buf = initial_buf or []
    while True:
        try:
            s = os.read(fd, buffer_size)
        except OSError as e:
            if e.errno == errno.EIO:
                # If the child-facing PTY got closed, reading from the
                # parent-facing PTY raises EIO.
                break
            raise
        if not s:
            break
        buf.append(s)
    return b''.join(buf)


class TestStdio(unittest.TestCase):
    def _test(
        self,
        child_script,
        stream,
        rwpair_generator,
        check_output,
        python_args=[],
        post_child_check=None,
        stdin_generator=None,
    ):
        assert stream in ('stdout', 'stderr')
        if stdin_generator is None:
            stdin_generator = open(os.devnull, 'rb')
        with rwpair_generator() as (
            stream_receiver,
            child_stream,
        ), stdin_generator as child_stdin:
            proc = subprocess.Popen(
                [sys.executable] + python_args + ['-c', child_script],
                stdin=child_stdin,
                stdout=child_stream if stream == 'stdout' else None,
                stderr=child_stream if stream == 'stderr' else None,
            )
            try:
                os.close(child_stream)
                if stream_receiver is not None:
                    check_output(stream_receiver, proc)
            except:  # re-raises
                proc.terminate()
                raise
            finally:
                retcode = proc.wait()
            self.assertEqual(retcode, 0)
            if post_child_check is not None:
                post_child_check()

    def _test_buffering(
        self, stream, rwpair_generator, expected_output, python_args=[]
    ):
        def check_output(stream_receiver, proc):
            self.assertEqual(_readall(stream_receiver, 1024), expected_output)

        self._test(
            TEST_BUFFERING_CHILD_SCRIPT.format(stream=stream),
            stream,
            rwpair_generator,
            check_output,
            python_args,
        )

    def test_buffering_stdout_devnull(self):
        self._test_buffering('stdout', _devnull, None)

    def test_buffering_stdout_pipes(self):
        self._test_buffering('stdout', _pipes, FULLY_BUFFERED)

    def test_buffering_stdout_ptys(self):
        self._test_buffering('stdout', _ptys, LINE_BUFFERED)

    def test_buffering_stdout_devnull_unbuffered(self):
        self._test_buffering('stdout', _devnull, None, python_args=['-u'])

    def test_buffering_stdout_pipes_unbuffered(self):
        self._test_buffering('stdout', _pipes, UNBUFFERED, python_args=['-u'])

    def test_buffering_stdout_ptys_unbuffered(self):
        self._test_buffering('stdout', _ptys, UNBUFFERED, python_args=['-u'])

    def _test_large_write(self, stream, rwpair_generator, python_args=[]):
        def check_output(stream_receiver, proc):
            if not pycompat.iswindows:
                # On Unix, we can provoke a partial write() by interrupting it
                # by a signal handler as soon as a bit of data was written.
                # We test that write() is called until all data is written.
                buf = [os.read(stream_receiver, 1)]
                proc.send_signal(signal.SIGINT)
            else:
                # On Windows, there doesn't seem to be a way to cause partial
                # writes.
                buf = []
            self.assertEqual(
                _readall(stream_receiver, 131072, buf), b'x' * 1048576
            )

        def post_child_check():
            self.assertEqual(write_result_f.read(), '1048576')

        with tempfile.NamedTemporaryFile('r') as write_result_f:
            self._test(
                TEST_LARGE_WRITE_CHILD_SCRIPT.format(
                    stream=stream, write_result_fn=write_result_f.name
                ),
                stream,
                rwpair_generator,
                check_output,
                python_args,
                post_child_check=post_child_check,
            )

    def test_large_write_stdout_devnull(self):
        self._test_large_write('stdout', _devnull)

    def test_large_write_stdout_pipes(self):
        self._test_large_write('stdout', _pipes)

    def test_large_write_stdout_ptys(self):
        self._test_large_write('stdout', _ptys)

    def test_large_write_stdout_devnull_unbuffered(self):
        self._test_large_write('stdout', _devnull, python_args=['-u'])

    def test_large_write_stdout_pipes_unbuffered(self):
        self._test_large_write('stdout', _pipes, python_args=['-u'])

    def test_large_write_stdout_ptys_unbuffered(self):
        self._test_large_write('stdout', _ptys, python_args=['-u'])

    def test_large_write_stderr_devnull(self):
        self._test_large_write('stderr', _devnull)

    def test_large_write_stderr_pipes(self):
        self._test_large_write('stderr', _pipes)

    def test_large_write_stderr_ptys(self):
        self._test_large_write('stderr', _ptys)

    def test_large_write_stderr_devnull_unbuffered(self):
        self._test_large_write('stderr', _devnull, python_args=['-u'])

    def test_large_write_stderr_pipes_unbuffered(self):
        self._test_large_write('stderr', _pipes, python_args=['-u'])

    def test_large_write_stderr_ptys_unbuffered(self):
        self._test_large_write('stderr', _ptys, python_args=['-u'])

    def _test_broken_pipe(self, stream):
        assert stream in ('stdout', 'stderr')

        def check_output(stream_receiver, proc):
            os.close(stream_receiver)
            proc.stdin.write(b'x')
            proc.stdin.close()

        def post_child_check():
            err = pickle.load(err_f)
            self.assertEqual(err.errno, errno.EPIPE)
            self.assertEqual(err.strerror, "Broken pipe")

        with tempfile.NamedTemporaryFile('rb') as err_f:
            self._test(
                TEST_BROKEN_PIPE_CHILD_SCRIPT.format(
                    stream=stream, err_fn=err_f.name
                ),
                stream,
                _pipes,
                check_output,
                post_child_check=post_child_check,
                stdin_generator=util.nullcontextmanager(subprocess.PIPE),
            )

    def test_broken_pipe_stdout(self):
        self._test_broken_pipe('stdout')

    def test_broken_pipe_stderr(self):
        self._test_broken_pipe('stderr')


if __name__ == '__main__':
    import silenttestrunner

    silenttestrunner.main(__name__)
