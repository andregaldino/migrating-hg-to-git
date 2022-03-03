#!/usr/bin/env python3
#
# This is literally `cat` but in python, one char at a time.
#
# see sigpipe-remote.py for details.

import io
import os
import sys


if isinstance(sys.stdout.buffer, io.BufferedWriter):
    print('SIGPIPE-WORKER: script need unbuffered output', file=sys.stderr)
    sys.exit(255)

while True:
    c = os.read(sys.stdin.fileno(), 1)
    os.write(sys.stdout.fileno(), c)
