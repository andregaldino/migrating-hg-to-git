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

import jinja2

from .py2exe import (
    build_py2exe,
    stage_install,
)
from .util import find_vc_runtime_files

EXTRA_PACKAGES = {
    'dulwich',
    'keyring',
    'pygments',
    'win32ctypes',
}

PACKAGE_FILES_METADATA = {
    'ReadMe.html': 'Flags: isreadme',
}


def build(
    source_dir: pathlib.Path,
    build_dir: pathlib.Path,
    python_exe: pathlib.Path,
    iscc_exe: pathlib.Path,
    version=None,
):
    """Build the Inno installer.

    Build files will be placed in ``build_dir``.

    py2exe's setup.py doesn't use setuptools. It doesn't have modern logic
    for finding the Python 2.7 toolchain. So, we require the environment
    to already be configured with an active toolchain.
    """
    if not iscc_exe.exists():
        raise Exception('%s does not exist' % iscc_exe)

    vc_x64 = r'\x64' in os.environ.get('LIB', '')
    arch = 'x64' if vc_x64 else 'x86'
    inno_source_dir = source_dir / 'contrib' / 'packaging' / 'inno'
    inno_build_dir = build_dir / ('inno-%s' % arch)
    staging_dir = inno_build_dir / 'stage'

    requirements_txt = (
        source_dir / 'contrib' / 'packaging' / 'inno' / 'requirements.txt'
    )

    inno_build_dir.mkdir(parents=True, exist_ok=True)

    build_py2exe(
        source_dir,
        build_dir,
        python_exe,
        'inno',
        requirements_txt,
        extra_packages=EXTRA_PACKAGES,
    )

    # Purge the staging directory for every build so packaging is
    # pristine.
    if staging_dir.exists():
        print('purging %s' % staging_dir)
        shutil.rmtree(staging_dir)

    # Now assemble all the packaged files into the staging directory.
    stage_install(source_dir, staging_dir)

    # hg.exe depends on VC9 runtime DLLs. Copy those into place.
    for f in find_vc_runtime_files(vc_x64):
        if f.name.endswith('.manifest'):
            basename = 'Microsoft.VC90.CRT.manifest'
        else:
            basename = f.name

        dest_path = staging_dir / basename

        print('copying %s to %s' % (f, dest_path))
        shutil.copyfile(f, dest_path)

    # The final package layout is simply a mirror of the staging directory.
    package_files = []
    for root, dirs, files in os.walk(staging_dir):
        dirs.sort()

        root = pathlib.Path(root)

        for f in sorted(files):
            full = root / f
            rel = full.relative_to(staging_dir)
            if str(rel.parent) == '.':
                dest_dir = '{app}'
            else:
                dest_dir = '{app}\\%s' % rel.parent

            package_files.append(
                {
                    'source': rel,
                    'dest_dir': dest_dir,
                    'metadata': PACKAGE_FILES_METADATA.get(str(rel), None),
                }
            )

    print('creating installer')

    # Install Inno files by rendering a template.
    jinja_env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(inno_source_dir)),
        # Need to change these to prevent conflict with Inno Setup.
        comment_start_string='{##',
        comment_end_string='##}',
    )

    try:
        template = jinja_env.get_template('mercurial.iss')
    except jinja2.TemplateSyntaxError as e:
        raise Exception(
            'template syntax error at %s:%d: %s'
            % (e.name, e.lineno, e.message,)
        )

    content = template.render(package_files=package_files)

    with (inno_build_dir / 'mercurial.iss').open('w', encoding='utf-8') as fh:
        fh.write(content)

    # Copy additional files used by Inno.
    for p in ('mercurial.ico', 'postinstall.txt'):
        shutil.copyfile(
            source_dir / 'contrib' / 'win32' / p, inno_build_dir / p
        )

    args = [str(iscc_exe)]

    if vc_x64:
        args.append('/dARCH=x64')

    if version:
        args.append('/dVERSION=%s' % version)

    args.append('/Odist')
    args.append(str(inno_build_dir / 'mercurial.iss'))

    subprocess.run(args, cwd=str(source_dir), check=True)
