from __future__ import absolute_import, print_function

import re
import sys

print(re.sub(r"(?<=Message-Id:) \n ", " ", sys.stdin.read()), end="")
