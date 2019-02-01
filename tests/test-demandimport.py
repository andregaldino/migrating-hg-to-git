from __future__ import absolute_import, print_function

from mercurial import demandimport
demandimport.enable()

import os
import subprocess
import sys

# Only run if demandimport is allowed
if subprocess.call(['python', '%s/hghave' % os.environ['TESTDIR'],
                    'demandimport']):
    sys.exit(80)

# We rely on assert, which gets optimized out.
if sys.flags.optimize:
    sys.exit(80)

if os.name != 'nt':
    try:
        import distutils.msvc9compiler
        print('distutils.msvc9compiler needs to be an immediate '
              'importerror on non-windows platforms')
        distutils.msvc9compiler
    except ImportError:
        pass

import re

rsub = re.sub
def f(obj):
    l = repr(obj)
    l = rsub("0x[0-9a-fA-F]+", "0x?", l)
    l = rsub("from '.*'", "from '?'", l)
    l = rsub("'<[a-z]*>'", "'<whatever>'", l)
    return l

demandimport.disable()
os.environ['HGDEMANDIMPORT'] = 'disable'
# this enable call should not actually enable demandimport!
demandimport.enable()
from mercurial import node

# We use assert instead of a unittest test case because having imports inside
# functions changes behavior of the demand importer.
assert f(node) == "<module 'mercurial.node' from '?'>", f(node)

# now enable it for real
del os.environ['HGDEMANDIMPORT']
demandimport.enable()

# Test access to special attributes through demandmod proxy
from mercurial import error as errorproxy
assert f(errorproxy) == "<unloaded module 'error'>", f(errorproxy)
doc = ' '.join(errorproxy.__doc__.split()[:3])
assert doc == 'Mercurial exceptions. This', doc
assert errorproxy.__name__ == 'mercurial.error', errorproxy.__name__

# __name__ must be accessible via __dict__ so the relative imports can be
# resolved
name = errorproxy.__dict__['__name__']
assert name == 'mercurial.error', name

assert f(errorproxy) == "<proxied module 'error'>", f(errorproxy)

import os

assert f(os) == "<unloaded module 'os'>", f(os)
assert f(os.system) == '<built-in function system>', f(os.system)
assert f(os) == "<module 'os' from '?'>", f(os)

from mercurial.utils import procutil

assert f(procutil) == "<unloaded module 'procutil'>", f(procutil)
assert f(procutil.system) == '<function system at 0x?>', f(procutil.system)
assert f(procutil) == "<module 'mercurial.utils.procutil' from '?'>", f(
    procutil
)
assert f(procutil.system) == '<function system at 0x?>', f(procutil.system)

from mercurial import hgweb
assert f(hgweb) == "<unloaded module 'hgweb'>", f(hgweb)
assert f(hgweb.hgweb_mod) == "<unloaded module 'hgweb_mod'>", f(hgweb.hgweb_mod)
assert f(hgweb) == "<module 'mercurial.hgweb' from '?'>", f(hgweb)

import re as fred
assert f(fred) == "<unloaded module 're'>", f(fred)

import re as remod
assert f(remod) == "<unloaded module 're'>", f(remod)

import sys as re
assert f(re) == "<unloaded module 'sys'>", f(re)

assert f(fred) == "<unloaded module 're'>", f(fred)
assert f(fred.sub) == '<function sub at 0x?>', f(fred.sub)
assert f(fred) == "<proxied module 're'>", f(fred)

remod.escape  # use remod
assert f(remod) == "<module 're' from '?'>", f(remod)

assert f(re) == "<unloaded module 'sys'>", f(re)
assert f(re.stderr) == "<open file '<whatever>', mode 'w' at 0x?>", f(re.stderr)
assert f(re) == "<proxied module 'sys'>", f(re)

import contextlib
assert f(contextlib) == "<unloaded module 'contextlib'>", f(contextlib)
try:
    from contextlib import unknownattr

    assert False, (
        'no demandmod should be created for attribute of non-package '
        'module:\ncontextlib.unknownattr = %s' % f(unknownattr)
    )
except ImportError as inst:
    assert rsub(r"'", '', str(inst)) == 'cannot import name unknownattr'

from mercurial import util

# Unlike the import statement, __import__() function should not raise
# ImportError even if fromlist has an unknown item
# (see Python/import.c:import_module_level() and ensure_fromlist())
contextlibimp = __import__('contextlib', globals(), locals(), ['unknownattr'])
assert f(contextlibimp) == "<module 'contextlib' from '?'>", f(contextlibimp)
assert not util.safehasattr(contextlibimp, 'unknownattr')
