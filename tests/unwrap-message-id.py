from __future__ import absolute_import, print_function

import sys

for line in sys.stdin:
    if line.lower() in ("message-id: \n", "in-reply-to: \n"):
        line = line[:-2]
    print(line, end="")
