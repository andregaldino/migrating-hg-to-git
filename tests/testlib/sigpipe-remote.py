#!/usr/bin/env python3

import io
import os
import subprocess
import sys
import time


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


def sysbytes(s):
    return s.encode('utf-8')


def sysstr(s):
    return s.decode('latin-1')


debug_stream.write(b'SIGPIPE-HELPER: Starting\n')

TESTLIB_DIR = os.path.dirname(sys.argv[0])
WAIT_SCRIPT = os.path.join(TESTLIB_DIR, 'wait-on-file')

hooks_cmd = '%s 10 %s %s'
hooks_cmd %= (
    WAIT_SCRIPT,
    SYNCFILE2,
    SYNCFILE1,
)

try:
    cmd = ['hg']
    cmd += sys.argv[1:]
    sub = subprocess.Popen(
        cmd,
        bufsize=0,
        close_fds=True,
        stdin=sys.stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    basedir = os.path.dirname(sys.argv[0])
    worker = os.path.join(basedir, 'sigpipe-worker.py')

    cmd = [sys.executable, worker]

    stdout_worker = subprocess.Popen(
        cmd,
        bufsize=0,
        close_fds=True,
        stdin=sub.stdout,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )

    stderr_worker = subprocess.Popen(
        cmd,
        bufsize=0,
        close_fds=True,
        stdin=sub.stderr,
        stdout=sys.stderr,
        stderr=sys.stderr,
    )
    debug_stream.write(b'SIGPIPE-HELPER: Redirection in place\n')
    os.close(sub.stdout.fileno())
    os.close(sub.stderr.fileno())
    debug_stream.write(b'SIGPIPE-HELPER: pipes closed in main\n')

    try:
        wait_file(sysbytes(SYNCFILE1))
    except RuntimeError as exc:
        msg = sysbytes(str(exc))
        debug_stream.write(b'SIGPIPE-HELPER: wait failed: %s\n' % msg)
    else:
        debug_stream.write(b'SIGPIPE-HELPER: SYNCFILE1 detected\n')
    stdout_worker.kill()
    stderr_worker.kill()
    stdout_worker.wait(10)
    stderr_worker.wait(10)
    debug_stream.write(b'SIGPIPE-HELPER: worker killed\n')

    debug_stream.write(b'SIGPIPE-HELPER: creating SYNCFILE2\n')
    write_file(sysbytes(SYNCFILE2))
finally:
    debug_stream.write(b'SIGPIPE-HELPER: Shutting down\n')
    if not sys.stdin.closed:
        sys.stdin.close()
    try:
        sub.wait(timeout=30)
    except subprocess.TimeoutExpired:
        msg = b'SIGPIPE-HELPER: Server process failed to terminate\n'
        debug_stream.write(msg)
        sub.kill()
        sub.wait()
        msg = b'SIGPIPE-HELPER: Server process killed\n'
    else:
        msg = b'SIGPIPE-HELPER: Server process terminated with status %d\n'
        msg %= sub.returncode
        debug_stream.write(msg)
    debug_stream.write(b'SIGPIPE-HELPER: Shut down\n')
