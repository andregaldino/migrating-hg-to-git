#!/usr/bin/env python3
from __future__ import print_function

import io
import os
import subprocess
import sys
import threading
import time

# we cannot use mercurial.testing as long as python2 is not dropped as the test will only install the mercurial module for python2 in python2 run

if isinstance(sys.stdout.buffer, io.BufferedWriter):
    print('SIGPIPE-HELPER: script need unbuffered output', file=sys.stderr)
    sys.exit(255)

DEBUG_FILE = os.environ.get('SIGPIPE_REMOTE_DEBUG_FILE')
if DEBUG_FILE is None:
    debug_stream = sys.stderr.buffer
else:
    debug_stream = open(DEBUG_FILE, 'bw', buffering=0)

SYNCFILE1 = os.environ.get('SYNCFILE1')
SYNCFILE2 = os.environ.get('SYNCFILE2')
if SYNCFILE1 is None:
    print('SIGPIPE-HELPER: missing variable $SYNCFILE1', file=sys.stderr)
    sys.exit(255)
if SYNCFILE2 is None:
    print('SIGPIPE-HELPER: missing variable $SYNCFILE2', file=sys.stderr)
    sys.exit(255)


def _timeout_factor():
    """return the current modification to timeout"""
    default = int(os.environ.get('HGTEST_TIMEOUT_DEFAULT', 360))
    current = int(os.environ.get('HGTEST_TIMEOUT', default))
    if current == 0:
        return 1
    return current / float(default)


def wait_file(path, timeout=10):
    timeout *= _timeout_factor()
    start = time.time()
    while not os.path.exists(path):
        if (time.time() - start) > timeout:
            raise RuntimeError(b"timed out waiting for file: %s" % path)
        time.sleep(0.01)


def write_file(path, content=b''):
    with open(path, 'wb') as f:
        f.write(content)


# end of mercurial.testing content

if sys.version_info[0] < 3:
    print('SIGPIPE-HELPER: script should run with Python 3', file=sys.stderr)
    sys.exit(255)


def sysbytes(s):
    return s.encode('utf-8')


def sysstr(s):
    return s.decode('latin-1')


piped_stdout = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
piped_stderr = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)

stdout_writer = os.fdopen(piped_stdout[1], "rb")
stdout_reader = os.fdopen(piped_stdout[0], "rb")
stderr_writer = os.fdopen(piped_stderr[1], "rb")
stderr_reader = os.fdopen(piped_stderr[0], "rb")

debug_stream.write(b'SIGPIPE-HELPER: Starting\n')

TESTLIB_DIR = os.path.dirname(sys.argv[0])
WAIT_SCRIPT = os.path.join(TESTLIB_DIR, 'wait-on-file')

hooks_cmd = '%s 10 %s %s'
hooks_cmd %= (
    WAIT_SCRIPT,
    SYNCFILE2,
    SYNCFILE1,
)

cmd = ['hg']
cmd += sys.argv[1:]
sub = subprocess.Popen(
    cmd,
    bufsize=0,
    close_fds=True,
    stdin=sys.stdin,
    stdout=stdout_writer,
    stderr=stderr_writer,
)

debug_stream.write(b'SIGPIPE-HELPER: Mercurial started\n')


shut_down = threading.Event()

close_lock = threading.Lock()


def _read(stream):
    try:
        return stream.read()
    except ValueError:
        # read on closed file
        return None


def forward_stdout():
    while not shut_down.is_set():
        c = _read(stdout_reader)
        while c is not None:
            sys.stdout.buffer.write(c)
            c = _read(stdout_reader)
        time.sleep(0.001)
    with close_lock:
        if not stdout_reader.closed:
            stdout_reader.close()
            debug_stream.write(b'SIGPIPE-HELPER: stdout closed\n')


def forward_stderr():
    while not shut_down.is_set():
        c = _read(stderr_reader)
        if c is not None:
            sys.stderr.buffer.write(c)
            c = _read(stderr_reader)
        time.sleep(0.001)
    with close_lock:
        if not stderr_reader.closed:
            stderr_reader.close()
            debug_stream.write(b'SIGPIPE-HELPER: stderr closed\n')


stdout_thread = threading.Thread(target=forward_stdout, daemon=True)
stderr_thread = threading.Thread(target=forward_stderr, daemon=True)

try:
    stdout_thread.start()
    stderr_thread.start()

    debug_stream.write(b'SIGPIPE-HELPER: Redirection in place\n')

    try:
        wait_file(sysbytes(SYNCFILE1))
    except RuntimeError as exc:
        msg = sysbytes(str(exc))
        debug_stream.write(b'SIGPIPE-HELPER: wait failed: %s\n' % msg)
    else:
        debug_stream.write(b'SIGPIPE-HELPER: SYNCFILE1 detected\n')
    with close_lock:
        if not stdout_reader.closed:
            stdout_reader.close()
        if not stderr_reader.closed:
            stderr_reader.close()
        sys.stdin.close()
        debug_stream.write(b'SIGPIPE-HELPER: pipes closed\n')
    debug_stream.write(b'SIGPIPE-HELPER: creating SYNCFILE2\n')
    write_file(sysbytes(SYNCFILE2))
finally:
    debug_stream.write(b'SIGPIPE-HELPER: Shutting down\n')
    shut_down.set()
    if not sys.stdin.closed:
        sys.stdin.close()
    try:
        sub.wait(timeout=30)
    except subprocess.TimeoutExpired:
        msg = b'SIGPIPE-HELPER: Server process failed to terminate\n'
        debug_stream.write(msg)
    else:
        debug_stream.write(b'SIGPIPE-HELPER: Server process terminated\n')
    debug_stream.write(b'SIGPIPE-HELPER: Shut down\n')
