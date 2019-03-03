#!/usr/bin/env python3
# build.py - Inno installer build script.
#
# Copyright 2019 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# This script automates the building of the Inno MSI installer for Mercurial.

# no-check-code because Python 3 native.

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile


DOWNLOADS = {
    'gettext': {
        'url': 'https://versaweb.dl.sourceforge.net/project/gnuwin32/gettext/0.14.4/gettext-0.14.4-bin.zip',
        'size': 1606131,
        'sha256': '60b9ef26bc5cceef036f0424e542106cf158352b2677f43a01affd6d82a1d641',
        'version': '0.14.4',
    },
    'gettext-dep': {
        'url': 'https://versaweb.dl.sourceforge.net/project/gnuwin32/gettext/0.14.4/gettext-0.14.4-dep.zip',
        'size': 715086,
        'sha256': '411f94974492fd2ecf52590cb05b1023530aec67e64154a88b1e4ebcd9c28588',
    },
    'py2exe': {
        'url': 'https://versaweb.dl.sourceforge.net/project/py2exe/py2exe/0.6.9/py2exe-0.6.9.zip',
        'size': 149687,
        'sha256': '6bd383312e7d33eef2e43a5f236f9445e4f3e0f6b16333c6f183ed445c44ddbd',
        'version': '0.6.9',
    },
    'virtualenv': {
        'url': 'https://files.pythonhosted.org/packages/37/db/89d6b043b22052109da35416abc3c397655e4bd3cff031446ba02b9654fa/virtualenv-16.4.3.tar.gz',
        'size': 3713208,
        'sha256': '984d7e607b0a5d1329425dd8845bd971b957424b5ba664729fab51ab8c11bc39',
        'version': '16.4.3',
    },
}


PRINT_PYTHON_INFO = '''
import platform, sys; print("%s:%d" % (platform.architecture()[0], sys.version_info[0]))
'''.strip()


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


def build(source_dir: pathlib.Path, build_dir: pathlib.Path,
          python_exe: pathlib.Path, iscc_exe: pathlib.Path,
          version=None):
    """Build the Inno installer.

    Build files will be placed in ``build_dir``.

    py2exe's setup.py doesn't use setuptools. It doesn't have modern logic
    for finding the Python 2.7 toolchain. So, we require the environment
    to already be configured with an active toolchain.
    """
    from packagingutil import (
        download_entry,
        extract_tar_to_directory,
        extract_zip_to_directory,
    )

    if not iscc.exists():
        raise Exception('%s does not exist' % iscc)

    if 'VCINSTALLDIR' not in os.environ:
        raise Exception('not running from a Visual C++ build environment; '
                        'execute the "Visual C++ <version> Command Prompt" '
                        'application shortcut or a vcsvarsall.bat file')

    # Identity x86/x64 and validate the environment matches the Python
    # architecture.
    vc_x64 = r'\x64' in os.environ['LIB']

    res = subprocess.run(
        [str(python_exe), '-c', PRINT_PYTHON_INFO],
        capture_output=True, check=True)

    py_arch, py_version = res.stdout.decode('utf-8').split(':')
    py_version = int(py_version)

    if vc_x64:
        if py_arch != '64bit':
            raise Exception('architecture mismatch: Visual C++ environment '
                            'is configured for 64-bit but Python is 32-bit')
    else:
        if py_arch != '32bit':
            raise Exception('architecture mismatch: Visual C++ environment '
                            'is configured for 32-bit but Python is 64-bit')

    if py_version != 2:
        raise Exception('Only Python 2 is currently supported')

    build_dir.mkdir(exist_ok=True)

    gettext_pkg = download_entry(DOWNLOADS['gettext'], build_dir)
    gettext_dep_pkg = download_entry(DOWNLOADS['gettext-dep'], build_dir)
    virtualenv_pkg = download_entry(DOWNLOADS['virtualenv'], build_dir)
    py2exe_pkg = download_entry(DOWNLOADS['py2exe'], build_dir)

    venv_path = build_dir / ('venv-inno-%s' % ('x64' if vc_x64 else 'x86'))

    gettext_root = build_dir / (
        'gettext-win-%s' % DOWNLOADS['gettext']['version'])

    if not gettext_root.exists():
        extract_zip_to_directory(gettext_pkg, gettext_root)
        extract_zip_to_directory(gettext_dep_pkg, gettext_root)

    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)

        # This assumes Python 2.
        extract_tar_to_directory(virtualenv_pkg, td)
        extract_zip_to_directory(py2exe_pkg, td)

        virtualenv_src_path = td / ('virtualenv-%s' %
            DOWNLOADS['virtualenv']['version'])
        py2exe_source_path = td / ('py2exe-%s' %
            DOWNLOADS['py2exe']['version'])

        virtualenv_py = virtualenv_src_path / 'virtualenv.py'

        if not venv_path.exists():
            print('creating virtualenv with dependencies')
            subprocess.run(
                [str(python_exe), str(virtualenv_py), str(venv_path)],
                check=True)

        venv_python = venv_path / 'Scripts' / 'python.exe'
        venv_pip = venv_path / 'Scripts' / 'pip.exe'

        requirements_txt = (source_dir / 'contrib' / 'packaging' /
                            'inno' / 'requirements.txt')
        subprocess.run([str(venv_pip), 'install', '-r', str(requirements_txt)],
                       check=True)

        # Force distutils to use VC++ settings from environment, which was
        # validated above.
        env = dict(os.environ)
        env['DISTUTILS_USE_SDK'] = '1'
        env['MSSdk'] = '1'

        py2exe_py_path = venv_path / 'Lib' / 'site-packages' / 'py2exe'
        if not py2exe_py_path.exists():
            print('building py2exe')
            subprocess.run([str(venv_python), 'setup.py', 'install'],
                           cwd=py2exe_source_path,
                           env=env,
                           check=True)

        # Register location of msgfmt and other binaries.
        env['PATH'] = '%s%s%s' % (
            env['PATH'], os.pathsep, str(gettext_root / 'bin'))

        print('building Mercurial')
        subprocess.run(
            [str(venv_python), 'setup.py',
             'py2exe', '-b', '3' if vc_x64 else '2',
             'build_doc', '--html'],
            cwd=str(source_dir),
            env=env,
            check=True)

        # hg.exe depends on VC9 runtime DLLs. Copy those into place.
        for f in find_vc_runtime_files(vc_x64):
            if f.name.endswith('.manifest'):
                basename = 'Microsoft.VC90.CRT.manifest'
            else:
                basename = f.name

            dest_path = source_dir / 'dist' / basename

            print('copying %s to %s' % (f, dest_path))
            shutil.copyfile(f, dest_path)

        print('creating installer')

        args = [str(iscc_exe)]

        if vc_x64:
            args.append('/dARCH=x64')

        if version:
            args.append('/dVERSION=%s' % version)

        args.append('/Odist')
        args.append('contrib/packaging/inno/mercurial.iss')

        subprocess.run(args, cwd=str(source_dir), check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()

    parser.add_argument('--python',
                        required=True,
                        help='path to python.exe to use')
    parser.add_argument('--iscc',
                        help='path to iscc.exe to use')
    parser.add_argument('--version',
                        help='Mercurial version string to use '
                             '(detected from __version__.py if not defined')

    args = parser.parse_args()

    if args.iscc:
        iscc = pathlib.Path(args.iscc)
    else:
        iscc = (pathlib.Path(os.environ['ProgramFiles(x86)']) / 'Inno Setup 5' /
            'ISCC.exe')

    here = pathlib.Path(os.path.abspath(os.path.dirname(__file__)))
    source_dir = here.parent.parent.parent
    build_dir = source_dir / 'build'

    sys.path.insert(0, str(source_dir / 'contrib' / 'packaging'))

    build(source_dir, build_dir, pathlib.Path(args.python), iscc,
          version=args.version)
