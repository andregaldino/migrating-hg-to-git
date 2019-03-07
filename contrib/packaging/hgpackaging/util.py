# util.py - Common packaging utility code.
#
# Copyright 2019 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# no-check-code because Python 3 native.

import distutils.version
import os
import pathlib
import subprocess
import tarfile
import zipfile


def extract_tar_to_directory(source: pathlib.Path, dest: pathlib.Path):
    with tarfile.open(source, 'r') as tf:
        tf.extractall(dest)


def extract_zip_to_directory(source: pathlib.Path, dest: pathlib.Path):
    with zipfile.ZipFile(source, 'r') as zf:
        zf.extractall(dest)


def find_vc_runtime_files(x64=False):
    """Finds Visual C++ Runtime DLLs to include in distribution."""
    winsxs = pathlib.Path(os.environ['SYSTEMROOT']) / 'WinSxS'

    prefix = 'amd64' if x64 else 'x86'

    candidates = sorted(p for p in os.listdir(winsxs)
                  if p.lower().startswith('%s_microsoft.vc90.crt_' % prefix))

    for p in candidates:
        print('found candidate VC runtime: %s' % p)

    # Take the newest version.
    version = candidates[-1]

    d = winsxs / version

    return [
        d / 'msvcm90.dll',
        d / 'msvcp90.dll',
        d / 'msvcr90.dll',
        winsxs / 'Manifests' / ('%s.manifest' % version),
    ]


PRINT_PYTHON_INFO = '''
import platform; print("%s:%s" % (platform.architecture()[0], platform.python_version()))
'''.strip()


def python_exe_info(python_exe: pathlib.Path):
    """Obtain information about a Python executable."""

    res = subprocess.run(
        [str(python_exe), '-c', PRINT_PYTHON_INFO],
        capture_output=True, check=True)

    arch, version = res.stdout.decode('utf-8').split(':')

    version = distutils.version.LooseVersion(version)

    return {
        'arch': arch,
        'version': version,
        'py3': version >= distutils.version.LooseVersion('3'),
    }
