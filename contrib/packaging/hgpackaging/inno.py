# inno.py - Inno Setup functionality.
#
# Copyright 2019 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# no-check-code because Python 3 native.

import os
import pathlib
import shutil
import subprocess

from .downloads import (
    download_entry,
)
from .util import (
    extract_tar_to_directory,
    extract_zip_to_directory,
    find_vc_runtime_files,
)


PRINT_PYTHON_INFO = '''
import platform, sys; print("%s:%d" % (platform.architecture()[0], sys.version_info[0]))
'''.strip()


def build(source_dir: pathlib.Path, build_dir: pathlib.Path,
          python_exe: pathlib.Path, iscc_exe: pathlib.Path,
          version=None):
    """Build the Inno installer.

    Build files will be placed in ``build_dir``.

    py2exe's setup.py doesn't use setuptools. It doesn't have modern logic
    for finding the Python 2.7 toolchain. So, we require the environment
    to already be configured with an active toolchain.
    """
    if not iscc_exe.exists():
        raise Exception('%s does not exist' % iscc_exe)

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

    gettext_pkg, gettext_entry = download_entry('gettext', build_dir)
    gettext_dep_pkg = download_entry('gettext-dep', build_dir)[0]
    virtualenv_pkg, virtualenv_entry = download_entry('virtualenv', build_dir)
    py2exe_pkg, py2exe_entry = download_entry('py2exe', build_dir)

    venv_path = build_dir / ('venv-inno-%s' % ('x64' if vc_x64 else 'x86'))

    gettext_root = build_dir / (
        'gettext-win-%s' % gettext_entry['version'])

    if not gettext_root.exists():
        extract_zip_to_directory(gettext_pkg, gettext_root)
        extract_zip_to_directory(gettext_dep_pkg, gettext_root)

    # This assumes Python 2. We don't need virtualenv on Python 3.
    virtualenv_src_path = build_dir / (
        'virtualenv-%s' % virtualenv_entry['version'])
    virtualenv_py = virtualenv_src_path / 'virtualenv.py'

    if not virtualenv_src_path.exists():
        extract_tar_to_directory(virtualenv_pkg, build_dir)

    py2exe_source_path = build_dir / ('py2exe-%s' % py2exe_entry['version'])

    if not py2exe_source_path.exists():
        extract_zip_to_directory(py2exe_pkg, build_dir)

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
